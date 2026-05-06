# Next Bench Session - UDP Policy Gateway (2026-05-05)

The project has moved from "make W5500 MACRAW behave like a transparent
Ethernet firewall" to a shippable W5500 UDP packet-policy gateway. MACRAW is
kept as diagnostic history. The final demo uses W5500 A UDP sockets, FPGA
stream classification/signature matching, and W5500 B transmit.

## What Is Proven

| Layer | Status |
| --- | --- |
| PC1 normal UDP/static-ARP sender | OK. tcpdump repeatedly showed real unicast frames leaving `en0` for `02:00:00:de:ad:0a`. |
| W5500 A PHY/link | OK. SignalTap readback showed `PHYCFGR=0xBF` -> 100M full duplex. |
| W5500 A MACRAW for demo UDP/80 | Not reliable on this bench. It surfaced background traffic but not the verified demo unicast. |
| W5500 A UDP socket ingress | OK. Round 22 proved UDP/80 reaches the FPGA stream path. |
| FPGA stream path and W5500 B TX | OK. Round 22 showed matching A/B first bytes, B SEND clears, and zero timeouts. |
| PC2 visibility | OK for the UDP socket path. User confirmed dashboard and Wireshark show packets arriving. |

## Final Demo Image

The current flashed SOF checksum is `0x085DC65F` and includes:

- W5500 A socket 0: UDP/80 allow/demo service.
- W5500 A socket 1: UDP/5001 file/sine/data allow service.
- W5500 A socket 2: UDP/5002 decoy/drop service.
- FPGA policy counters:
  - UDP/80 allow,
  - UDP/5001 allow,
  - UDP/5002 drop,
  - content-block drop,
  - default drop.
- Streaming payload signatures:
  - `FWFILE1\0` -> file telemetry,
  - `FWSINE2\0` -> sine telemetry,
  - `FW-BLOCK` / `FW-DEMO-DROP` -> content-block override.

## Bench Protocol

1. Use the already-flashed `0x085DC65F` image, or recompile/flash `build/quartus/de1_soc_w5500.sof` if RTL changes.
2. Use normal forwarding mode:
   - `SW0=1`
   - `SW5=0`
   - `SW7=0`
3. Reset or let the flash reset the board, then wait for:
   - `LEDR0=1`
   - `LEDR1=0`
4. Wait at least 30 seconds after flash/reset.
5. PC1 setup:
   ```bash
   sudo ifconfig en0 inet 192.168.1.10 netmask 255.255.255.0 up
   sudo arp -d 192.168.1.1 2>/dev/null || true
   sudo arp -s 192.168.1.1 02:00:00:de:ad:0a
   python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 1 --verbose-each
   ```
6. PC1 sanity capture:
   ```bash
   sudo tcpdump -i en0 -nn -e -c 20 'udp port 80 or udp port 5001 or udp port 5002'
   ```
7. PC2 dashboard:
   ```powershell
   py -3 scripts\rule_demo_receiver_dashboard.py --iface Ethernet --uart COM7 --port 8091
   ```
   If UART is not wired or the COM port differs, omit `--uart` for packet-only
   proof and use SignalTap for FPGA counters.
8. PC2 Wireshark display filters:
   - allowed traffic: `udp.port == 80 || udp.port == 5001`
   - decoy leak check: `udp.port == 5002 || frame contains "FW-BLOCK" || frame contains "FW-DEMO-DROP"`

## UART Adapter Wiring

The dashboard's FPGA histogram needs a separate 3.3 V TTL USB-UART adapter.
The DE1-SoC USB-Blaster/JTAG cable does not carry this UART.

```text
DE1-SoC GPIO_0_D6 / GPIO_0[6]  ->  USB-UART RXD
DE1-SoC GND                    ->  USB-UART GND
```

Use `115200 8N1`, no flow control. Do not connect USB-UART `5V` to the board,
and do not use an RS-232 serial adapter. The FPGA UART is transmit-only, so
USB-UART `TXD` is not needed. In Windows Device Manager, use the assigned COM
port in the dashboard command, for example `--uart COM7`.

The dashboard line chart in the Live Result panel uses a rolling wall-clock
window, not packet index. If traffic stops, the graph keeps moving and falls to
zero instead of freezing on the last packet.

## SignalTap Proof

Use force export first because the old trigger setup is still B-TX-oriented:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' `
  -t scripts\signaltap_capture_force.tcl `
  quartus\de1_soc_w5500.stp `
  captures\stp\udp_policy_gateway.csv 10
py -3 scripts\inspect_signaltap_csv.py captures\stp\udp_policy_gateway.csv
```

Expected high-level evidence:

- `PHYCFGR=0xBF`
- W5500 A UDP socket status open (`0x22`) while running.
- UDP/80 and UDP/5001 rule counters rise.
- UDP/5002 and content-block counters rise when decoys are enabled.
- B buffer writes, SEND issued, SEND cleared, and B TX count rise for allowed packets.
- B SEND timeouts stay at zero.

If new `stp_rule_*` nodes are added to the `.stp`, remember that SignalTap
requires saving the `.stp`, recompiling Quartus, and flashing the matching SOF.

## Acceptance

- PC2 sees UDP/80 and UDP/5001 allowed packets.
- PC2 does not see UDP/5002 packets.
- PC2 does not see packets whose payload contains `FW-BLOCK` or `FW-DEMO-DROP`.
- UART or SignalTap counters prove the blocked packets were seen and dropped by
  FPGA policy logic.
- The file demo dashboard on `http://127.0.0.1:8092` reconstructs the real file,
  shows chunk progress/missing chunks/leaks, previews the completed file when the
  browser supports the MIME type, and reports matching SHA-256 while decoys are
  dropped.
- Use the file sender's default `--chunk-size 256` for the live demo. A 512-byte
  file chunk becomes a 604-byte FPGA-internal frame after the `FWFILE1` header
  and synthesized Ethernet/IP/UDP wrapper. If the flashed image/path still has a
  512-byte frame guard, full chunks are discarded and only the final short chunk
  reaches PC2.
- Use file sender default `--interval 0.10` for hardware bring-up. First run
  `--decoys 0 --limit-chunks 4` to prove allowed UDP/5001 chunks reach PC2,
  then run the full `--decoys 1` checksum proof. The old `--interval 0.01` burst
  can overrun the two-W5500 path and make PC2 appear silent.
- The payload waveform dashboard on `http://127.0.0.1:8090` shows the signed
  int16 sample values carried in UDP/5001 packets as dots on a moving time
  axis; missing packets leave visible blank intervals instead of being
  connected across.
- The waveform x-axis defaults to real packet-arrival time. One vertical grid
  column is one second, and no fake zero line is drawn when samples are absent.
  Keep receiver `--time-mode arrival` for the live demo.
- `scripts/sine_sender.py` can now generate `sine`, `square`, `triangle`,
  `saw`, `step`, `noise`, literal `--wave values`, or 5x7 `--wave text`
  streams. The receiver plots the received payload values only, so a square-wave
  packet stream renders as a square wave and arbitrary values render as
  themselves.

## If Something Fails

| Observation | Action |
| --- | --- |
| PC1 tcpdump does not show demo packets | Fix PC1 interface/static ARP/sender first. |
| FPGA counters do not rise | Debug W5500 A UDP socket status and RX commits. Do not return to MACRAW. |
| Allow counters rise but B TX does not | Debug FIFO/forwarder/B TX handoff. |
| B TX rises but PC2 sees nothing | Debug PC2 NIC, cable, Wireshark filter, and dashboard interface selection. |
| Block counters rise and PC2 also sees blocked traffic | Fix content-block/drop decision in `firewall_forwarder`. |

## Upgrades After Submission

- Runtime rule configuration over UART or a register bus.
- Larger parallel signature engine.
- Deterministic latency timestamping from A RX to B TX.
- Token-bucket rate limiting per rule.
- Transparent L2/TCP firewalling with a true Ethernet MAC/PHY instead of W5500 sockets.
