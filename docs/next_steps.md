# Next Steps

## Immediate path
1. Run the dedicated testbenches in this order: source, parser, rules, buffer, firewall core, SPI, adapter
2. Confirm parser fields line up with the packet vectors in `tb/packets/`
3. Expand `rule_engine.v` from parameterized rules into a BRAM-backed table when the baseline is stable
4. Replace the adapter shell transaction bytes with the chosen Ethernet controller's real register map
5. Decide whether buffering should stay single-packet for MVP or become a small packet FIFO

## Once hardware arrives
1. Verify SPI wiring and reset
2. Read a known register repeatedly
3. Complete the init sequence
4. Read one real packet
5. Compare bytes against Wireshark
6. Feed those bytes into the existing firewall core
7. Only then attempt second-port forwarding
