# Architecture

## Phase 1: Core Firewall in Simulation
`fake_eth_source -> packet_buffer -> eth_ipv4_parser -> rule_engine -> allow/drop counters`

## Phase 2: One-Port Hardware Bring-Up
`ethernet_controller_adapter_rx -> internal frame interface -> firewall_core`

## Phase 3: Optional Forwarding
`firewall_core allow -> packet_buffer_tx -> ethernet_controller_adapter_tx`

## Internal principle
The firewall core must not care whether packets come from:
- fake simulation source
- packet memory file
- real Ethernet controller

That boundary is the main risk-reduction mechanism.
