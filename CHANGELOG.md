# CHANGELOG

## 2026-04-08
- Created the repository structure from the project planning document
- Added project docs, milestone flow, and helper scripts
- Added synthesizable RTL for SPI, parser, rule engine, packet buffer, controller adapter shell, firewall core, and top-level integration
- Added packet vectors and dedicated simulation testbenches
- Added a PowerShell simulation helper for local `iverilog` runs
- Added a mixed-language verification flow with shared SystemVerilog testbench utilities
- Converted the parser, rule engine, and firewall core benches to SystemVerilog
- Added an SSH-allow TCP packet vector to improve rule and integration coverage

## 2026-04-09
- Fixed remaining simulation pulse-capture issues in the rule engine and packet buffer benches
- Updated the SPI master to support multi-byte transactions with held chip-select
- Replaced the placeholder adapter with a W5500-oriented MACRAW RX path
- Added a reusable W5500 SPI/RX simulation model and adapter-to-firewall integration bench
- Added a DE1-SoC board wrapper and froze the first GPIO wiring contract in docs
- Added an XSim suite runner and a Scapy-based deterministic packet sender scaffold for physical testing

## 2026-04-16
- Added `docs/project_overview.md` as a newcomer-friendly project guide covering goals, architecture, stages, testing flow, deployment, hardware, and key files
