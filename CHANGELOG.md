# CHANGELOG

## 2026-04-08
- Bootstrapped the repository structure from `firewall_repo_bootstrap.md`
- Added project docs, milestone flow, and helper scripts
- Added synthesizable starter RTL for SPI, parser, rule engine, packet buffer, controller adapter shell, firewall core, and top-level integration
- Added packet vectors and dedicated simulation testbenches
- Added a PowerShell simulation helper for local `iverilog` runs
- Added a mixed-language verification flow with shared SystemVerilog testbench utilities
- Converted the parser, rule engine, and firewall core benches to SystemVerilog
- Added an SSH-allow TCP packet vector to improve rule and integration coverage
