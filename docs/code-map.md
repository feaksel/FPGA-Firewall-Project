# Code Map

This page is a practical map of the source tree.

## Top-Level RTL

| File | Role |
| --- | --- |
| `rtl/top/de1_soc_w5500_top.v` | DE1-SoC board wrapper, switches, LEDs, HEX pages, W5500 A/B connections |
| `rtl/top/firewall_top.v` | reusable receive/firewall integration wrapper |

## Ethernet and W5500

| File | Role |
| --- | --- |
| `rtl/eth_if/w5500_udp_rx_adapter.v` | final W5500 A UDP socket receive path |
| `rtl/eth_if/w5500_macraw_tx_adapter.v` | W5500 B transmit adapter |
| `rtl/eth_if/w5500_tx_engine.v` | W5500 TX-buffer writer and SEND engine |
| `rtl/eth_if/ethernet_controller_adapter.v` | older MACRAW receive adapter, kept for diagnostic history |
| `rtl/spi/spi_master.v` | shared SPI master |

## Policy Logic

| File | Role |
| --- | --- |
| `rtl/firewall/firewall_forwarder.v` | current stream policy forwarder and signature scanner |
| `rtl/firewall/firewall_core.v` | parser/rule integration from the original firewall core |
| `rtl/parser/eth_ipv4_parser.v` | Ethernet II + IPv4 + TCP/UDP field parser |
| `rtl/rules/rule_engine.v` | parameterized first-match rule engine |
| `rtl/buffer/packet_buffer.v` | packet storage and replay |
| `rtl/buffer/frame_rx_fifo.v` | RX-side frame FIFO for backpressure |

## Debug RTL

| File | Role |
| --- | --- |
| `rtl/debug/debug_counters.v` | basic counters |
| `rtl/debug/seven_seg_hex.v` | HEX digit decoder |
| `rtl/debug/uart_tx.v` | UART byte transmitter |
| `rtl/debug/firewall_telemetry_uart.v` | ASCII telemetry line generator |

## Testbenches and Models

| Folder | Role |
| --- | --- |
| `tb/tests/` | individual testbenches |
| `tb/models/` | W5500 and fake Ethernet models |
| `tb/common/` | shared SystemVerilog package/helpers |
| `tb/packets/` | packet memory vectors |

Important newer benches:
- `w5500_udp_rx_adapter_tb.sv`
- `w5500_tx_engine_tb.sv`
- `firewall_forwarder_tb.sv`
- `de1_soc_top_udp_socket_forward_tb.sv`

## PC and Demo Scripts

| Script | Role |
| --- | --- |
| `scripts/rule_demo_udp_socket_sender.py` | PC1 sender for the simple policy demo |
| `scripts/rule_demo_receiver_dashboard.py` | PC2 rule dashboard and optional UART histogram |
| `scripts/file_sender.py` | PC1 chunked file sender with decoys |
| `scripts/file_receiver.py` | PC2 file reconstruction and SHA-256 dashboard |
| `scripts/media_demo_sender.py` | convenience sender for checked-in demo media |
| `scripts/photo_stream_sender.py` | repeated still-image transfer |
| `scripts/webcam_photo_sender.py` | OpenCV webcam snapshot sender |
| `scripts/sine_sender.py` | PC1 payload waveform sender |
| `scripts/sine_receiver_dashboard.py` | PC2 waveform dashboard |
| `scripts/pcap_summary.py` | pcap marker summary helper |
| `scripts/inspect_signaltap_csv.py` | SignalTap CSV decoder |

## Build and Simulation Scripts

| Script | Role |
| --- | --- |
| `scripts/run_xsim_suite.ps1` | main XSim regression suite |
| `scripts/run_xsim.ps1` | single XSim testbench |
| `scripts/run_questa.ps1` | single Questa console test |
| `scripts/run_questa_gui.ps1` | Questa GUI launch |
| `scripts/run_iverilog.ps1` | Icarus Verilog fallback |
| `scripts/create_quartus_project.ps1` | Quartus project refresh wrapper |
