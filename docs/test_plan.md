# Test Plan

## Milestone 1: Packet Source Simulation
Pass criteria:
- fake packet source emits bytes from memory file
- SOP and EOP positions are correct
- packet length counted correctly

Move on when:
- at least one IPv4 TCP vector streams correctly

## Milestone 2: Parser
Pass criteria:
- extracts EtherType
- extracts src/dst IP
- extracts protocol
- extracts src/dst ports for TCP/UDP

Move on when:
- `parser_tb` passes for TCP and UDP vectors

## Milestone 3: Rule Engine
Pass criteria:
- exact IP match works
- subnet mask match works
- port range match works
- default DROP works
- first-match priority works

Move on when:
- `rule_engine_tb` passes all cases

## Milestone 4: Firewall Core
Pass criteria:
- parser + rule engine connected
- counts received / allowed / dropped
- actions match test vectors

Move on when:
- `firewall_core_tb` passes a mixed packet set

## Milestone 5: SPI Master
Pass criteria:
- mode settings stable
- clock generation correct
- shift timing correct in simulation

Move on when:
- `spi_master_tb` passes a loopback or known-response transfer

## Milestone 6: Controller Adapter Shell
Pass criteria:
- W5500-oriented init FSM compiles
- read/write transaction sequence defined
- MACRAW RX path documented and simulated
- RX FIFO path can absorb backpressure without changing firewall decisions

Move on when:
- `eth_controller_adapter_tb` passes and `adapter_firewall_integration_tb` passes

## Milestone 6.5: RX FIFO Hardening
Pass criteria:
- FIFO preserves data, SOP, EOP, and source-port metadata
- FIFO handles backpressure
- FIFO reports overflow when the queue is intentionally overfilled

Move on when:
- `frame_rx_fifo_tb` passes
- the integrated adapter-to-firewall bench still passes with FIFO enabled

## Milestone 7: One-Port Hardware Bring-Up
Pass criteria:
- controller responds to register reads
- initialization sequence stable
- real packet received

Move on when:
- packet bytes visible in a debug path

## Milestone 8: Real One-Way Inline Forwarding
Pass criteria:
- `firewall_forwarder_tb` proves allowed packets replay and dropped packets do not
- `w5500_tx_engine_tb` proves TX buffer writes, `S0_TX_WR` update, and `SEND`
- W5500 B reset/init works on hardware
- one fixed test frame is transmitted from FPGA to PC2
- one allowed PC1-to-PC2 packet appears on PC2
- one blocked packet is absent on PC2

Move on when:
- one-way `PC1 -> W5500 A -> FPGA -> W5500 B -> PC2` forwarding is repeatable

## Milestone 9: File/Video Demo

Pass criteria:
- PC1 sends chunked file/video traffic on UDP destination port `5001`
- decoy/error frames are interleaved and blocked
- PC2 reconstructs the file with matching SHA-256
- UART/dashboard counters agree with observed PC2 packets

Move on when:
- the final presentation can show forwarded, dropped, lost/error, throughput, chunk-map, and checksum status clearly
