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
- Updated `README.md` to reference the overview guide and give new teammates a clearer documentation entry path
- Added an RX-side frame FIFO between the Ethernet adapter and firewall core, plus a dedicated FIFO testbench and FIFO-enabled integration coverage
- Hardened the DE1-SoC top-level with synchronized reset release and synchronized board-control sampling for the live hardware path
- Removed the Quartus SPI truncation warnings and the `KEY[0]` global-clock warning from the current build flow
- Validated the updated pre-hardware flow with full XSim regression, a Questa smoke check, and a fresh Quartus compile that emits `build/quartus/de1_soc_w5500.sof`
