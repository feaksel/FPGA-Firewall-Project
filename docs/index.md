# ELE432 FPGA UDP Policy Gateway

This documentation describes the current state of the ELE432 Ethernet/FPGA
project. The project started as an FPGA firewall idea, but the realistic
hardware result is a W5500-based UDP policy gateway.

The working demo path is:

```text
PC1 sender -> W5500 A -> FPGA parser/policy/forwarder -> W5500 B -> PC2 receiver
```

The FPGA receives UDP traffic through W5500 A, rebuilds an internal packet byte
stream, checks a small policy, and forwards only allowed traffic through W5500
B. PC2 then shows whether the correct packets arrived and whether blocked
traffic leaked.

## Project Goal

The goal is to show a real FPGA datapath making network policy decisions:
- parse packet-like byte streams
- classify UDP services
- scan payload markers
- count allow/drop decisions
- forward allowed packets
- block selected traffic
- prove the result using simulation, board counters, SignalTap, Wireshark, and
  browser dashboards

This is not trying to pretend the W5500 socket mode is a full transparent
firewall. The documentation is written around what the hardware can actually
show.

## Best Reading Order

1. [Current status](status.md)
2. [Architecture](architecture.md)
3. [Hardware setup](hardware.md)
4. [Demo guide](demo.md)
5. [Simulation and tests](verification.md)
6. [Quartus build](quartus.md)
7. [Code map](code-map.md)
8. [Interfaces](interfaces.md)
9. [Debugging notes](debugging.md)

The older long-form notes, debug logs, contribution rules, and session plans are
kept in [the archive](archive/README.md).

## Main Evidence Sources

For this project, a claim is only considered proven when it has the right kind
of evidence:

| Claim | Evidence |
| --- | --- |
| RTL behavior works | passing simulation testbench |
| W5500 registers work | SPI readback and init state |
| packets reach the FPGA | HEX/LED counters or SignalTap |
| packets are forwarded | PC2 Wireshark/dashboard sees them |
| packets are blocked | PC2 sees no leak and FPGA counters show drops |
| file transfer works | PC2 SHA-256 matches PC1 |

That separation matters because FPGA counters alone can be misleading if the
W5500 or PC capture side is not actually seeing the same thing.
