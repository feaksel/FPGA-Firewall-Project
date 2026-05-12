# Demo Guide

The safest demo order is:

1. Start the PC2 receiver/dashboard.
2. Program and start the FPGA in normal mode.
3. Start the PC1 sender at conservative pacing.
4. Check PC2 packets and FPGA counters.
5. Only then try faster or more visual modes.

## Network Shape

```text
PC1 Ethernet -> W5500 A -> DE1-SoC FPGA -> W5500 B -> PC2 Ethernet
```

Use normal mode on the board:

```text
SW0=1, SW5=0, SW6=0, SW7=0, SW8=0, SW9=0
```

The examples use `en0` for PC1 and `Ethernet` for PC2. Replace those with the
real interface names on your machines.

## Simple Rule Demo

Start PC2 first:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --port 8091
```

Open:

```text
http://127.0.0.1:8091
```

Start PC1:

```bash
sudo python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 1 --verbose-each
```

Expected result:
- UDP/80 allowed count rises.
- UDP/5001 allowed count rises.
- UDP/5002 leak count stays at zero.
- `FW-BLOCK` / `FW-DEMO-DROP` leak count stays at zero.
- FPGA receive/allow/drop counters move on HEX pages or UART.

## File Transfer Demo

Start PC2:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092
```

Open:

```text
http://127.0.0.1:8092
```

First run a small allow-path probe from PC1:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 0 --limit-chunks 4 --interval 0.10
```

Then run the full policy proof:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 1 --interval 0.10
```

Expected result:
- PC2 receives UDP/5001 chunks.
- UDP/5002 and `FW-BLOCK` decoys do not appear on PC2.
- The dashboard reconstructs the file.
- SHA-256 matches when every allowed chunk arrives.

Do not use `--interval 0.001` for the reliable proof. That is a stress setting.
Because this is raw UDP, one missing allowed chunk correctly prevents a final
SHA-256 pass.

## Quick Media Demo

The repo includes media under `demo files/` for the visual transfer demo.

Start PC2 with the same file receiver, then run:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0
```

For policy proof with media:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 1
```

If chunks are randomly missing, use retry passes instead of sending faster:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0 --retry-passes 3
```

## Waveform Demo

Start PC2:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090
```

Open:

```text
http://127.0.0.1:8090
```

Start PC1:

```bash
sudo python3 scripts/sine_sender.py --iface en0 --wave sine --wave-hz 1 --packets-per-second 5
```

The PC2 dashboard plots signed sample values carried inside UDP/5001 payloads.
It is not drawing a fake sine wave locally. Missing allowed packets appear as
real gaps.

Other sender patterns:

```bash
sudo python3 scripts/sine_sender.py --iface en0 --wave square --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave triangle --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave text --text "FPGA UDP" --sample-rate 210 --samples-per-packet 21 --packets-per-second 10
```

## Useful Wireshark Filters

Allowed data:

```text
udp.port == 5001
```

Blocked traffic that should not appear on PC2:

```text
udp.port == 5002
```

```text
frame contains "FW-BLOCK" || frame contains "FW-DEMO-DROP"
```

## Interface Name Help

On PC2, list capture interfaces with:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --list-ifaces
```

If the dashboard stays empty but Wireshark sees traffic, the Python script is
probably sniffing the wrong interface.
