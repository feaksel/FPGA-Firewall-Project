# Current Status

The latest status recorded in the repository is from 2026-05-07. I am keeping
that date explicit because the hardware notes are tied to actual bench sessions.

## Working Hardware Path

The proven path is the one-way UDP policy gateway:

```text
PC1 -> W5500 A UDP socket RX -> FPGA policy path -> W5500 B TX -> PC2
```

Current working pieces:
- DE1-SoC programs successfully through USB-Blaster/JTAG.
- W5500 modules respond to SPI register access.
- W5500 A can receive UDP socket traffic from PC1.
- W5500 B can transmit to PC2.
- UDP/80 traffic has been forwarded to PC2.
- UDP/5001 file-demo chunks have been forwarded to PC2.
- The long-frame bug in `firewall_forwarder.v` was fixed by widening the byte
  index to 16 bits.
- PC2 Npcap/Wireshark captured `FWFILE1\0` UDP/5001 chunks after that fix.

## Current Demo Policy

| Profile | Expected decision |
| --- | --- |
| UDP destination port `80` | allow |
| UDP destination port `5001` | allow |
| UDP destination port `5002` | drop |
| allowed service with `FW-BLOCK` payload | drop |
| allowed service with `FW-DEMO-DROP` payload | drop |

The file demo uses UDP/5001 with a `FWFILE1\0` marker. The waveform demo uses
UDP/5001 with a `FWSINE2\0` marker.

## Still Open

The main unfinished presentation proof is:

```text
full file transfer at safe pacing -> decoys included -> zero leaks -> SHA-256 PASS
```

The hardware has already shown forwarded safe-size UDP/5001 chunks, but the
full file proof is stricter because every allowed chunk must arrive. Since the
transport is raw UDP, the receiver should not pass the file if even one chunk is
missing.

## Historical Path

The older MACRAW/raw Ethernet work is preserved in the archive. It helped with
bring-up and debugging, but it is not the accepted final hardware path. The
current docs use the UDP socket path because that is the path backed by the
latest hardware evidence.

## Honest Scope

This project demonstrates a hardware packet-policy pipeline. It does not claim:
- transparent bidirectional bridging
- TCP session inspection
- TCP/SSH firewall enforcement on the final W5500 socket demo
- reliable file transport
- production-ready network security

Those would be future architecture changes, not small documentation edits.
