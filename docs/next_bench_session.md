# Next Bench Session — Round 2 Diagnostics

This is the cheat-sheet for the very next bring-up session. The previous SignalTap
capture (`captures/stp/after_reflash_sender_running.csv`) caught a Mac-origin
IPv6 background frame, not the demo IPv4/UDP-80 frame, so the question
"does the demo frame ever reach W5500 A?" was unanswerable from that capture.

Round-2 RTL adds an IPv4-only frame shadow plus per-ethertype frame counters,
so the next capture answers that question deterministically.

## What changed since the last reflash

- `de1_soc_w5500_top.v`:
  - Added `(* preserve, noprune *)` SignalTap probes:
    - `stp_a_rx_ipv4_first16[127..0]` — first 16 bytes of the most recent
      *IPv4* frame only.
    - `stp_frames_ipv4[31..0]`, `stp_frames_ipv6[31..0]`,
      `stp_frames_arp[31..0]`, `stp_frames_other[31..0]` — per-ethertype
      EOP counts on the rx_frame stream.
    - `stp_frames_udp_dport80[31..0]`, `stp_frames_demo_match[31..0]` —
      narrow counters for the demo profile.
- `scripts/inspect_signaltap_csv.py`:
  - Decodes the first 16 bytes into `dst / src / ethertype` rows.
  - Surfaces all six new counters.
  - Prints a one-line **Diagnosis** picking between five outcomes (see below).

## Step 1 — reflash and add the new probes

The new probes are `(* preserve, noprune *)` registers in the synthesized design,
so they're discoverable in SignalTap Node Finder once the new bitstream is loaded.

1. `cd quartus && quartus_sh.exe --flow compile de1_soc_w5500 -c de1_soc_w5500`
2. Open the existing `quartus/de1_soc_w5500.stp` via Quartus
   (`Tools -> SignalTap II Logic Analyzer`).
3. In Node Finder, type `stp_` and add:
   - `stp_a_rx_ipv4_first16[127..0]`
   - `stp_frames_ipv4[31..0]`
   - `stp_frames_ipv6[31..0]`
   - `stp_frames_arp[31..0]`
   - `stp_frames_other[31..0]`
   - `stp_frames_udp_dport80[31..0]`
   - `stp_frames_demo_match[31..0]`
4. Save the `.stp`, recompile, and program the board.

## Step 2 — bench setup

Same as before:

- DE1-SoC: `SW0=1`, `SW5..9=0`, press reset, wait for `LEDR0=1`, `LEDR1=0`.
- PC1 (Mac):

```bash
sudo python3 scripts/rule_demo_sender.py --iface en0 --rate 2 --packet-gap 0.05 \
    --no-ssh-allow --no-tcp-drop --verbose-each
```

Let it run for at least 5 seconds before capturing so several demo frames go past.

## Step 3 — capture and inspect

```powershell
quartus_stp.exe -t scripts/signaltap_capture.tcl `
    quartus/de1_soc_w5500.stp `
    captures/stp/round2.csv 30
py -3 scripts/inspect_signaltap_csv.py captures/stp/round2.csv
```

The inspect script's last block looks like this and tells you which branch we're in:

```text
Diagnosis:
  IPv4 frames              = 0x0000000A (10)
  IPv6 frames              = 0x00000003 (3)
  ARP frames               = 0x00000000 (0)
  Other frames             = 0x00000000 (0)
  IPv4 UDP dst=80 frames   = 0x0000000A (10)
  Demo-match frames        = 0x0000000A (10)
  B TX count               = 0x00000000 (0)
  B buf-writes             = 0x00000000 (0)
  ...
  CONCLUSION: ...
```

## Five possible outcomes and the next action for each

1. **`frames_ipv4 == 0` AND `frames_ipv6 > 0`** — only IPv6 background traffic
   reaches the W5500. The demo frame never makes it.
   - Run `sudo tcpdump -i en0 -nn -e udp port 80` on the Mac while the sender
     runs. If tcpdump shows nothing, Scapy is bound to the wrong NIC.
   - Confirm physical cable: PC1 → W5500 A.
   - Check if the Mac is sending IPv4 multicast on a different interface
     (e.g., a VPN like Cloudflare WARP or Tailscale stealing the route).

2. **`frames_ipv4 > 0` AND `frames_demo_match == 0`** — IPv4 frames reach A,
   but none are UDP/80.
   - `stp_a_rx_ipv4_first16` shows what the IPv4 frames actually look like.
     Decode it and compare with the expected demo bytes
     `01 00 5E 00 00 FB <Mac-MAC> 08 00 45 00 ...`.
   - Likely sender is sending TCP/SSH instead of UDP/80, or the dst port flag
     was overridden.

3. **`frames_demo_match > 0` AND `b_buf_writes == 0`** — demo frames reach A
   and parse correctly, but never get handed to W5500 B.
   - The break is in `frame_rx_fifo -> firewall_forwarder -> packet_buffer ->
     tx adapter`. Add `core_frame_valid`, `core_frame_ready`, `tx_frame_valid`,
     `tx_frame_ready`, `pkt_decision_seen`, `pkt_action_allow` to a fresh
     SignalTap probe set, trigger on `core_frame_eop && core_frame_ready`.
   - One possible RTL cause: rule 0 / rule 4 mis-fire as drop because of
     accidental matching. The forwarder rules are at
     [rtl/firewall/firewall_forwarder.v:212-273](rtl/firewall/firewall_forwarder.v#L212-L273).

4. **`b_buf_writes > 0` AND `b_tx_count == 0`** — B starts a buffer write but
   SEND never completes.
   - Trigger on `stp_b_send_timeouts[0]` rising. If it fires, the SEND command
     was issued but `S0_CR` never returned to `0x00`. That is a W5500-side
     issue (chip not responding) — check power / wiring.
   - If timeouts == 0 but tx_count == 0 too, the adapter is stuck in
     `ST_WAIT_SEND`. Capture `stp_adapter_b_state` rolling and confirm it sits
     at `0x10` (decimal 16).

5. **`b_tx_count > 0` AND PC2 dashboard sees nothing** — B is transmitting
   real frames but PC2 doesn't show them. The bug has moved to PC2.
   - Wireshark on PC2 with **no filter** first. If Wireshark sees the frames
     but the dashboard doesn't, the dashboard's filter is wrong (probably
     looking for `udp.port == 5001` instead of `udp.port == 80`).
   - If Wireshark sees nothing, the PC2 NIC is dropping the multicast at the
     hardware level. Solutions:
     - Add an IGMP join for `224.0.0.251` (`ip maddr add 224.0.0.251 dev <nic>`).
     - Switch the demo destination MAC to broadcast (`FF:FF:FF:FF:FF:FF`) by
       running `sudo python3 scripts/rule_demo_sender.py --iface en0
       --dst-mac FF:FF:FF:FF:FF:FF ...`. Broadcast is unconditionally accepted
       by every NIC and bypasses IGMP membership. We can switch back to
       multicast once the demo is proven.

## What probes to add to the .stp this time

Minimal "round 2" set, in priority order:

```text
stp_frames_ipv4[31..0]
stp_frames_ipv6[31..0]
stp_frames_udp_dport80[31..0]
stp_frames_demo_match[31..0]
stp_a_rx_ipv4_first16[127..0]
stp_a_rx_first16[127..0]
stp_b_tx_first16[127..0]
stp_b_buf_writes[31..0]
stp_b_send_issued[31..0]
stp_b_send_cleared[31..0]
stp_b_send_timeouts[31..0]
stp_b_tx_count[31..0]
stp_adapter_b_state[4..0]
stp_switches[9..0]
```

Trigger: leave at default (any sample after arming) for round 2. The new
counters are cumulative since reset, so a single late sample contains the
full history.

## What the RTL is doing under the hood

For each frame whose EOP fires on `rx_frame_*`:

- `rx_probe_byte_index`-driven case extracts ethertype (bytes 12-13),
  IP protocol (byte 23), and dst port (bytes 36-37).
- At EOP, the per-ethertype counter for `rx_probe_ethertype` is bumped:
  - `0x0800` -> `frames_ipv4_count++`, copy `a_rx_capture[0..15]` into
    `a_rx_ipv4_shadow[0..15]`. If `ip_proto == 0x11 && dst_port == 80`,
    also bump `frames_udp_dport80_count` and `frames_demo_match_count`.
  - `0x86DD` -> `frames_ipv6_count++`.
  - `0x0806` -> `frames_arp_count++`.
  - else     -> `frames_other_count++`.

So the IPv4 shadow only updates on a real IPv4 frame, and you can compare
"last frame seen at all" against "last IPv4 frame seen" to immediately tell
which path the chip is on.

## If the dashboard problem turns out to be PC2 only

If the round-2 capture confirms B is transmitting but PC2 simply isn't
displaying the frames, the FPGA bug is closed. The remaining work is on the
dashboard / NIC side and does not require any more bitstream changes.
