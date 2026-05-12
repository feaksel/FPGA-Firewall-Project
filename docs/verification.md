# Simulation and Tests

Simulation is still the fastest way to check the project. Hardware debugging is
slow, so the RTL should pass the relevant testbench before a change is trusted
on the DE1-SoC.

## Main XSim Suite

Run the suite from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim_suite.ps1
```

The current suite runs:

1. `fake_eth_source_tb`
2. `parser_tb`
3. `rule_engine_tb`
4. `packet_buffer_tb`
5. `frame_rx_fifo_tb`
6. `seven_seg_hex_tb`
7. `firewall_core_tb`
8. `spi_master_tb`
9. `eth_controller_adapter_tb`
10. `w5500_tx_engine_tb`
11. `adapter_firewall_integration_tb`
12. `two_port_bypass_tb`
13. `de1_soc_top_bypass_tb`

Run one testbench:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim.ps1 parser_tb
```

## Other Simulators

Questa console mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa.ps1 parser_tb
```

Questa GUI:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa_gui.ps1 parser_tb
```

Icarus Verilog:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_iverilog.ps1 parser_tb
```

## Focused Tests

The newer UDP gateway work also has focused benches that may be run separately,
depending on the simulator setup:

- `w5500_udp_rx_adapter_tb`
- `firewall_forwarder_tb`
- `w5500_tx_engine_tb`
- `de1_soc_top_udp_socket_forward_tb`
- `de1_soc_top_rule_regen_tb`
- `de1_soc_top_bypass_tb`

These tests check intended RTL handshakes against local models. They are not a
substitute for PC2 packet evidence, because the real W5500 modules and PC NICs
are part of the final system.

## Packet Vectors

The packet memory files are in `tb/packets/`:

- `udp_allow.mem`
- `tcp_drop.mem`
- `udp_subnet.mem`
- `tcp_allow_ssh.mem`

They are byte-per-line hex files used by the testbenches.

## What Each Layer Proves

| Layer | What should be checked |
| --- | --- |
| fake source | SOP/EOP, byte order, packet length |
| parser | EtherType, IPv4 protocol, IP addresses, TCP/UDP ports |
| rule engine | first-match priority, masks, port ranges, default drop |
| packet buffer | byte replay and packet boundary preservation |
| RX FIFO | backpressure and overflow behavior |
| SPI master | shift timing and response bytes |
| W5500 models | register sequence and buffer access shape |
| top-level benches | handoff between adapters, policy path, and TX path |

## Build Artifacts

Simulation outputs should stay under `build/`:

- `build/xsim/<testbench>/`
- `build/iverilog/<testbench>/`
- `build/questa/<testbench>/`

Generated simulator files should not be committed.
