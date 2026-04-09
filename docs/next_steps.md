# Next Steps

## Immediate path
1. Run `scripts/run_xsim_suite.ps1` and keep the full pre-hardware bench set passing
2. Validate the W5500 MACRAW adapter path with `adapter_firewall_integration_tb`
3. Freeze the DE1-SoC GPIO wiring in `docs/de1_soc_w5500_hardware.md`
4. Decide whether buffering should stay single-packet for MVP or become a small packet FIFO
5. Expand `rule_engine.v` from parameterized rules into a BRAM-backed table when the baseline is stable

## Once hardware arrives
1. Verify SPI wiring and reset
2. Read a known register repeatedly
3. Complete the init sequence
4. Read one real packet
5. Compare bytes against Wireshark
6. Feed those bytes into the existing firewall core
7. Only then attempt second-port forwarding
