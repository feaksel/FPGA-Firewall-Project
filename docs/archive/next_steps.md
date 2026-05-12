# Next Steps

This file is intentionally short. The detailed bench script is
[next_bench_session.md](/c:/Users/furka/Projects/ELE432_ethernet/docs/next_bench_session.md).

## Current Project Direction

Ship the project as a W5500-based UDP packet-policy gateway:

```text
PC1 UDP sender -> W5500 A UDP sockets -> FPGA parser/policy/signature logic -> W5500 B TX -> PC2 dashboard/Wireshark
```

The original transparent L2/MACRAW firewall attempt is kept as diagnostic
history in `BUGS.md`, `CHANGELOG.md`, and `docs/signaltap_debug.md`; it is not
the final demo path.

## Immediate Path

1. Keep the safe flashed image `0x085D8724` unless RTL changes.
2. Run the final file proof at safe pacing:
   `file_sender.py --decoys 1 --interval 0.10`.
3. Confirm PC2 `file_receiver.py` reconstructs the file, previews it when the
   MIME type is browser-supported, and reports SHA-256 PASS.
4. Confirm UDP/5002 and `FW-BLOCK` / `FW-DEMO-DROP` packets do not appear on
   PC2.
5. Capture SignalTap or UART/HEX proof that the FPGA classified the blocked
   profiles instead of the sender simply not sending them.

## After The Submission Demo Works

Good upgrades to leave open:

- runtime rule configuration over UART or a small register bus,
- deterministic latency measurement from A RX to B TX,
- token-bucket rate limiting per rule,
- larger parallel signature matching,
- a retransmission/ack layer for reliable UDP file transfer,
- true transparent L2/TCP firewalling with a real Ethernet MAC/PHY instead of
  W5500 socket abstraction.
