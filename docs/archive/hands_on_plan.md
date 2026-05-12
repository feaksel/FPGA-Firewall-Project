# DE1-SoC + W5500 Hands-On Plan

## Goal

This guide turns the current project state into a practical bench-to-board workflow:
- what to buy,
- how to connect the hardware,
- what to compile,
- how to program the FPGA,
- how to generate packet traffic from the PC,
- and what to check at each stage.

This plan assumes the hardware target remains:
- Terasic `DE1-SoC`
- W5500 Ethernet module over `SPI + RESET + INT`
- first-pass focus on RX inspection, parsing, and allow/drop counting

## 1. What to buy or gather

Minimum hardware:
- `DE1-SoC` board
- DE1-SoC power adapter
- USB cable for the DE1-SoC `USB-Blaster II` connection
- one `W5500` Ethernet module
- jumper wires or female-female Dupont wires
- one Ethernet cable
- a PC with an Ethernet port, or a USB-to-Ethernet adapter

Recommended Ethernet module:
- a `WIZ850io`-style W5500 module

Why this is the safest first choice:
- it already includes the RJ45 connector and magnetics,
- it exposes clean SPI/control pins,
- it is documented for `3.3 V` operation,
- and it matches the current SPI-based adapter design well.

Useful optional tools:
- a cheap logic analyzer for `SCLK`, `MOSI`, `MISO`, and `CS_n`
- a small unmanaged Ethernet switch if direct PC-to-module cabling is inconvenient

## 2. Voltage and wiring precautions

Use a `3.3 V` W5500 module and power it from the DE1-SoC `3.3 V` GPIO header supply.

Do not assume every W5500 breakout is equally suitable. For this project, prefer a module with:
- clearly documented `3.3 V` power,
- exposed `MOSI`, `MISO`, `SCLK`, `CS_n`, `INT_n`, and `RST_n`,
- and no ambiguity around SPI pin voltage levels.

The DE1-SoC GPIO headers expose `3.3 V`, `5 V`, and GND rails, so double-check the module power pin before connecting it.

## 3. Software to install on the PC

Required:
- `Quartus` for synthesis and programming
- DE1-SoC USB-Blaster driver support
- `Wireshark`

Already useful in this repo:
- `Vivado/XSim` for simulation regression

Recommended for deterministic traffic:
- Python 3
- Scapy

Install Scapy with:

```powershell
pip install scapy
```

## 4. Reconfirm the simulation baseline

Before touching hardware, rerun the full simulation suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim_suite.ps1
```

Current expected passing benches:
- `fake_eth_source_tb`
- `parser_tb`
- `rule_engine_tb`
- `packet_buffer_tb`
- `frame_rx_fifo_tb`
- `firewall_core_tb`
- `spi_master_tb`
- `eth_controller_adapter_tb`
- `adapter_firewall_integration_tb`

Simulation outputs are written under:
- `build/xsim/<testbench>/`
- `build/iverilog/<testbench>/`
- `build/questa/<testbench>/`

## 5. Create the Quartus project

The repo currently contains the synthesizable RTL and board-facing top module, but it does not yet contain a checked-in Quartus project layer such as:
- `.qpf`
- `.qsf`
- `.sdc`

Create a Quartus project that:
- uses the correct DE1-SoC device for your board revision,
- sets the top-level entity to `de1_soc_w5500_top`,
- includes the synthesizable files under `rtl/`,
- excludes all testbench files under `tb/`,
- and adds a basic clock constraint for `CLOCK_50`.

Use this top-level file:
- `rtl/top/de1_soc_w5500_top.v`

Important synthesizable modules in the current design:
- `rtl/top/de1_soc_w5500_top.v`
- `rtl/top/firewall_top.v`
- `rtl/eth_if/ethernet_controller_adapter.v`
- `rtl/firewall/firewall_core.v`
- `rtl/parser/eth_ipv4_parser.v`
- `rtl/rules/rule_engine.v`
- `rtl/spi/spi_master.v`
- `rtl/buffer/packet_buffer.v`
- `rtl/debug/debug_counters.v`

## 6. Apply the board pin mapping

Use the current frozen logical mapping from `docs/de1_soc_w5500_hardware.md`.

W5500 signal mapping:
- `GPIO_0[0]` -> `W5500 SCLK`
- `GPIO_0[1]` -> `W5500 MOSI`
- `GPIO_0[2]` -> `W5500 CS_n`
- `GPIO_0[3]` -> `W5500 RESET_n`
- `GPIO_0[4]` <- `W5500 MISO`
- `GPIO_0[5]` <- `W5500 INT_n`

Also connect:
- DE1-SoC `3.3 V` -> W5500 `3.3 V`
- DE1-SoC `GND` -> W5500 `GND`

Current LED debug mapping:
- `LEDR[0]` = `init_done`
- `LEDR[1]` = `init_error`
- `LEDR[2]` = `rx_packet_seen`
- `LEDR[6:3]` = adapter `debug_state`
- `LEDR[7]` = `rx_count[0]`
- `LEDR[8]` = `allow_count[0]`
- `LEDR[9]` = `drop_count[0]`

## 7. Physical wiring checklist

Before power-on:
1. Confirm the W5500 module power pin really expects `3.3 V`.
2. Confirm `MISO` is connected from module to FPGA input.
3. Confirm `MOSI`, `SCLK`, and `CS_n` go from FPGA to module.
4. Confirm `RESET_n` goes from FPGA to module.
5. Confirm `INT_n` goes from module to FPGA.
6. Confirm at least one common GND is connected.
7. Connect the Ethernet cable to the W5500 module RJ45.
8. Connect the USB-Blaster cable from the PC to the DE1-SoC.

## 8. Build the first FPGA image

Compile the design in Quartus with:
- top-level = `de1_soc_w5500_top`
- board clock = `CLOCK_50`

The first programming target should be a volatile SRAM/JTAG load:
- generate a `.sof`
- program it through JTAG

Expected handoff artifacts after compile:
- `build/quartus/de1_soc_w5500.sof`
- `build/quartus/de1_soc_w5500.pin`
- `build/quartus/de1_soc_w5500.fit.rpt`
- `build/quartus/de1_soc_w5500.sta.rpt`

Do not start with configuration flash programming. JTAG loading is faster and safer while the design is still changing.

## 9. Program the board

Use Quartus Programmer over the DE1-SoC USB-Blaster connection.

Suggested first-run board control state:
- `KEY[0]` released for normal design operation
- `SW[0] = 1` to start initialization

After programming:
- watch the LED outputs first,
- do not begin with Ethernet traffic until the init state looks reasonable.

## 10. First bring-up without relying on network behavior

Before sending packets, verify the basic hardware path:

1. Confirm the FPGA programs successfully.
2. Confirm the design is running from `CLOCK_50`.
3. Confirm `RESET_n` to the W5500 toggles during initialization.
4. Confirm `CS_n`, `SCLK`, and `MOSI` show SPI activity after `SW[0]` starts init.
5. Watch LEDs:
   - `LEDR[0]` should indicate `init_done`
   - `LEDR[1]` should indicate `init_error`
   - `LEDR[6:3]` should move through adapter state values during bring-up

If `init_done` never asserts:
- inspect `RESET_n`, `CS_n`, `SCLK`, `MOSI`, and `MISO` first,
- do not debug Ethernet traffic before SPI register access is behaving.

## 11. Connect the PC for traffic generation

Keep the PC connected to the board by USB-Blaster for reprogramming and debugging.

For Ethernet traffic, use one of these:
- direct PC NIC to W5500 module RJ45
- PC NIC and W5500 connected through a small unmanaged switch

Open Wireshark on the PC NIC that is connected to the W5500 side.

Important expectation:
- the current project is RX-path focused
- the FPGA is not expected to behave like a finished network endpoint yet
- `ping` timing out does not automatically mean the receive path is broken

What matters at this stage is:
- frames leave the PC,
- the W5500 receives them,
- the FPGA reads them,
- and the packet counters or debug LEDs react.

## 12. Generate initial traffic from the PC

Start with ordinary tools:
- Wireshark for capture
- `ping`
- `netcat` or `ncat`
- `iperf` later if basic packet reception is stable

This stage is mainly for:
- proving the link is alive,
- proving packets reach the W5500,
- and proving the FPGA sees activity.

## 13. Send deterministic packets

After basic SPI init and RX behavior look stable, use the included Scapy sender:
- `scripts/send_test_packets.py`

Examples:

```powershell
python .\scripts\send_test_packets.py --iface "Ethernet" --packet udp_allow
python .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_drop
python .\scripts\send_test_packets.py --iface "Ethernet" --packet tcp_allow_ssh
```

Use these packets to compare:
- what Wireshark shows,
- what the firewall is expected to parse,
- and whether the allow/drop counters respond as expected.

## 14. What success looks like at each stage

Stage 1 success:
- Quartus compiles cleanly
- FPGA programs over JTAG
- LEDs respond

Stage 2 success:
- W5500 reset timing is visible
- SPI transfers are visible
- adapter reaches `init_done`
- `init_error` stays inactive

Stage 3 success:
- `rx_packet_seen` toggles when the PC sends traffic
- counter LEDs show activity

Stage 4 success:
- `udp_allow` behaves like an allowed packet
- `tcp_drop` behaves like a dropped packet
- `tcp_allow_ssh` follows the expected rule behavior

## 14a. Current observed hardware status

As of 2026-05-01, the project has reached the following hardware state:

- DE1-SoC programming over JTAG works.
- W5500 `VERSIONR` register read works on the physical module.
- W5500 MACRAW initialization completes and reaches RX polling.
- `LEDR[0]` indicates `init_done`.
- `LEDR[1]` remains inactive during stable receive operation.
- `LEDR[2]` indicates that at least one packet has been seen.
- Deterministic Scapy packets from the PC were captured in Wireshark on the `Ethernet` interface:
  - `udp_allow`
  - `tcp_drop`
  - `tcp_allow_ssh`
- The FPGA receive/debug LEDs respond to traffic.

Important fixes discovered during bring-up:
- W5500 hardware reset delays must be much longer than simulation delays.
- The adapter wait counter must be wide enough for millisecond-scale board delays.
- W5500 SPI read/write control bytes must follow `RWB=0` for reads and `RWB=1` for writes.
- Real Ethernet RX can include background Windows multicast/broadcast traffic, so LEDs may move even when the deterministic sender is idle.

Current limitation:
- `LEDR[7]`, `LEDR[8]`, and `LEDR[9]` show only the low bit of RX/allow/drop counters. They are useful for activity, but not enough for clean per-packet allow/drop validation.

## 15. Recommended debug order if something fails

If the design does not compile:
1. Check Quartus top-level selection.
2. Check device selection for the exact DE1-SoC revision.
3. Check that only synthesizable `rtl/` files are in the project.
4. Check the board pin assignments and `CLOCK_50` constraint.

If the board programs but LEDs do nothing:
1. Check `KEY[0]` and `SW[0]`.
2. Check that the design is really using `de1_soc_w5500_top`.
3. Check clock and reset polarity assumptions.

If initialization fails:
1. Check `3.3 V` and GND at the W5500 module.
2. Check `RESET_n`.
3. Check `CS_n`, `SCLK`, and `MOSI`.
4. Check `MISO` direction and continuity.

Current accepted pre-hardware warnings:
- unused `KEY[1:3]` and `SW[1:9]`
- GPIO header structural warnings caused by the bidirectional `GPIO_0` wrapper style
- Quartus Lite subscription/license warnings

Warnings that should not reappear unnoticed:
- SPI truncation warnings
- `KEY[0]` being treated as a clock/global-clock source

If SPI init works but packets are not seen:
1. Check the Ethernet cable and link LEDs on the module.
2. Check Wireshark to make sure the PC is really sending frames.
3. Try the deterministic Scapy packets before more complicated traffic.
4. Only after polling RX is solid, consider enabling interrupt-driven handling later.

## 16. Recommended next repo task

The next practical repo task after the first hardware receive pass is to improve observability:
- expose fuller RX/allow/drop counters through a debug readout, UART, SignalTap, or a clearer LED mode,
- make a repeatable hardware smoke-test recipe for programming, sending deterministic packets, and checking expected counter movement,
- re-run the full simulation suite after the hardware-discovered W5500 SPI control-byte correction.

Do not begin forwarding until one-port allow/drop behavior is repeatable and documented.

## Sources

Official references used for this guide:
- Terasic DE1-SoC download index: https://download.terasic.com/downloads/cd-rom/de1-soc/
- WIZnet WIZ850io product page: https://wiznet.io/products/ethernet-modules/wiz850io
- WIZnet WIZ850io documentation: https://docs.wiznet.io/Product/ioModule/wiz850io
