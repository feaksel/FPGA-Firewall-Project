# Next Bench Session - Cheat Sheet (2026-05-05)

This is the working state after nineteen hardware-debug rounds. The important
decision is now made: do not keep chasing W5500 A MACRAW for the rule-demo
ingress. The current RTL checkpoint uses W5500 A normal UDP socket mode and
synthesizes the Ethernet/IP/UDP stream internally before the existing firewall
and W5500 B TX path.

## What We Know For Sure

| Layer | Status |
| --- | --- |
| PC1 normal UDP sender | OK. Fresh tcpdump showed `1c:f6:4c:44:ff:46 > 02:00:00:de:ad:0a`, IPv4, `192.168.1.10:4660 > 192.168.1.1:80`, 10/10 packets, zero drops. |
| Cable PC1 -> W5500 A | OK. Direct point-to-point, no switch. |
| W5500 A PHY | OK. `stp_phy_cfgr = 0xBF` -> link up, 100 Mbps, full duplex. |
| W5500 A common/register config | OK. Hardware readback proved `S0_MR=0x84`, `SHAR=02:00:00:DE:AD:0A`, `SIPR=192.168.1.1`. |
| W5500 A MACRAW for background traffic | Partly OK. It surfaces Mac broadcast/multicast background frames such as mDNS UDP/5353. |
| W5500 A MACRAW for demo UDP/80 | Not OK. It never surfaced the verified unicast UDP/80 demo packet. |
| FPGA parser/forwarder/B TX for surfaced frames | OK. Mac-origin mDNS frames were forwarded A -> FPGA -> B with zero B SEND timeouts. |
| W5500 B TX path | OK. Direct SW6 test and forwarded-background captures both prove B can transmit. |
| PC2 side | OK enough for current diagnosis. It has captured direct/generated/forwarded frames in earlier rounds. |

## Final MACRAW Evidence

Round 19 ran with the best possible MACRAW setup:

- PC1 sent normal UDP socket traffic to W5500 A:
  - destination MAC `02:00:00:de:ad:0a`
  - destination IP/port `192.168.1.1:80`
  - source `192.168.1.10:4660`
- W5500 A readbacks from the live chip:
  - `PHYCFGR=0xBF`
  - `S0_MR=0x84`
  - `SHAR=02:00:00:DE:AD:0A`
  - `SIPR=C0A80101`
- SignalTap still showed:
  - `frames_udp_dport80=0`
  - `frames_demo_match=0`
  - last IPv4 `dst_port=0x14E9` (UDP/5353 mDNS)

Conclusion: the hardware is not failing because of PC1, cable, PHY, SHAR,
SIPR, MFEN, parser, forwarder, or W5500 B TX. A-side MACRAW is simply not the
reliable rule-demo ingress path for this bench.

## Next Implementation Plan

Implement a new W5500 A UDP-socket RX adapter:

1. Program W5500 A common registers:
   - `SHAR = 02:00:00:DE:AD:0A`
   - `GAR = 192.168.1.10`
   - `SUBR = 255.255.255.0`
   - `SIPR = 192.168.1.1`
2. Open socket 0 in UDP mode on local port 80.
3. Poll `S0_RX_RSR`.
4. Read W5500 UDP RX records from the socket RX buffer.
5. Reconstruct an internal Ethernet/IP/UDP frame or equivalent parser metadata:
   - src MAC can be PC1's known MAC for the bench or a synthetic value
   - dst MAC should be W5500 A SHAR
   - src IP/port comes from the W5500 UDP record
   - dst IP/port is W5500 A SIPR / local UDP port 80
   - payload is the received UDP payload
6. Feed the reconstructed stream into the existing firewall/forwarder/B-TX path.

Keep W5500 B TX unchanged unless the new path reaches B and exposes a separate
B-side issue.

## Bench Protocol For The Next Image

1. PC1:
   ```bash
   sudo ifconfig en0 inet 192.168.1.10 netmask 255.255.255.0 up
   sudo arp -d 192.168.1.1 2>/dev/null || true
   sudo arp -s 192.168.1.1 02:00:00:de:ad:0a
   python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 2 --verbose-each
   ```
2. PC1 tcpdump sanity check:
   ```bash
   sudo tcpdump -i en0 -nn -e -c 10 'udp port 80 or arp'
   ```
3. Board:
   - flash the new SOF
   - wait for `LEDR0=1`, `LEDR1=0`
   - wait 30 seconds after flash/reset
4. Capture:
   ```powershell
   & 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' `
     -t scripts\signaltap_capture_force.tcl `
     quartus\de1_soc_w5500.stp `
     captures\stp\udp_socket_rx.csv 10
   py -3 scripts\inspect_signaltap_csv.py captures\stp\udp_socket_rx.csv
   ```

## Acceptance Criteria

- W5500 A UDP-mode RX observes PC1 packets at about the sender rate.
- Internal reconstructed frame/profile counts show UDP destination port 80.
- Existing B path completes SENDs with `b_send_timeouts=0`.
- PC2 Wireshark/dashboard sees the allowed demo frame.

## Round History

| Rounds | Result |
| --- | --- |
| 1-3 | Proved A/B path forwards some Mac-origin IPv4 background traffic, not demo UDP/80. |
| 4-5 | SHAR, RECV clear-poll, and S0_IR clear did not fix MACRAW. |
| 6-8 | PHY/read-size probes found bad-length discard churn; bounded discard fixed the worst misalignment behavior. |
| 9-13 | Faster A SPI drain, MFEN toggles, resync, and parser latches still showed no UDP/80. |
| 14-16 | Raw Scapy variants and normal UDP socket/static ARP were tested; PC1 was verified clean, but MACRAW still missed UDP/80. |
| 17-19 | Hardware readback proved W5500 A mode/MAC/IP are correct; MACRAW still missed UDP/80. Pivot to W5500 UDP socket RX. |
