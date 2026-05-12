# Debugging Notes

This page keeps the common bench checks in one place. The longer historical
debug notes are in the archive.

## Normal Demo Mode

Use this first:

```text
SW0=1, SW5=0, SW6=0, SW7=0, SW8=0, SW9=0
```

Expected during traffic:
- `LEDR[0]` is on for init done.
- `LEDR[1]` is off for no init error.
- receive count rises on HEX page `001`.
- allow count rises on HEX page `010`.
- drop count rises on HEX page `011` when decoys are enabled.
- W5500 B TX count rises on HEX page `101`.

## If PC2 Sees Nothing

Check in this order:

1. Make sure PC2 dashboard or Wireshark is on the Ethernet interface connected
   to W5500 B.
2. Confirm W5500 B TX count rises on HEX page `101`.
3. Use `SW6=1` direct B self-test. This ignores PC1 and sends a known generated
   frame to PC2.
4. If `SW6` works but normal mode does not, the problem is likely before or at
   the policy/TX handoff.
5. If `SW6` does not work, debug W5500 B wiring, PC2 interface, or the B TX
   adapter before looking at policy rules.

## If FPGA Counters Stay Flat

Briefly use W5500 A drain mode:

```text
SW5=1, SW9=0
```

This disables forwarding and only proves whether W5500 A is receiving and
streaming bytes. If A drain counts rise but normal receive counts do not, the
issue is downstream of W5500 A.

Return to normal mode after this check:

```text
SW5=0
```

## If File Transfer Misses Chunks

The file demo is raw UDP. Missing chunks are possible if the sender is too fast
or if capture/forwarding drops a packet.

Use the safe rate first:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 1 --interval 0.10
```

For visual media demos, use retries before increasing speed:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0 --retry-passes 3
```

Do not treat a failed SHA-256 as a dashboard bug. It is the correct behavior
when not every allowed chunk arrived.

## SignalTap Capture

Use SignalTap when board counters are not enough:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' -t scripts\signaltap_capture_force.tcl quartus\de1_soc_w5500.stp captures\stp\latest.csv 5
py -3 scripts\inspect_signaltap_csv.py captures\stp\latest.csv
```

Useful things to look for:
- W5500 A RX size
- synthesized frame length
- receive commit count
- policy allow/drop counters
- B TX buffer write count
- SEND issued and SEND cleared counts
- B SEND timeout count

## PCAP Summary

If a PC2 capture is confusing:

```powershell
py -3 scripts\pcap_summary.py C:\path\to\capture.pcapng
```

For the rule dashboard's own parser:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --pcap C:\path\to\capture.pcapng
```

Useful filters:

```text
udp.port == 5001
udp.port == 5002
frame contains "FW-BLOCK" || frame contains "FW-DEMO-DROP"
```
