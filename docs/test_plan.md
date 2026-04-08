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
- init FSM compiles
- read/write transaction sequence defined
- RX/TX states documented

Move on when:
- adapter shell reviewed and `eth_controller_adapter_tb` exists

## Milestone 7: One-Port Hardware Bring-Up
Pass criteria:
- controller responds to register reads
- initialization sequence stable
- real packet received

Move on when:
- packet bytes visible in a debug path

## Milestone 8: Optional Second-Port Forwarding
Pass criteria:
- second controller init works
- allowed packet transmitted out second side
- drop path remains correct

Move on when:
- demo works with simple traffic
