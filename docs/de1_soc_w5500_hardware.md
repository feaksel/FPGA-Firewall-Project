# DE1-SoC + W5500 Hardware Contract

## Board target

- FPGA board: Terasic DE1-SoC
- Ethernet module target: W5500
- MVP wiring: `SPI + RESET + INT`
- Clock source: `CLOCK_50`

## Top-level module

Use [de1_soc_w5500_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/de1_soc_w5500_top.v) as the board-facing wrapper.

Control assumptions:
- `KEY[0]` = active-high board reset release for the design
- `SW[0]` = start initialization

## GPIO_0 wiring contract

Freeze this logical mapping for the first hardware pass:

- `GPIO_0[0]` = W5500 `SCLK`
- `GPIO_0[1]` = W5500 `MOSI`
- `GPIO_0[2]` = W5500 `CS_n`
- `GPIO_0[3]` = W5500 `RESET_n`
- `GPIO_0[4]` = W5500 `MISO`
- `GPIO_0[5]` = W5500 `INT_n`

## LED debug contract

- `LEDR[0]` = `init_done`
- `LEDR[1]` = `init_error`
- `LEDR[2]` = `rx_packet_seen`
- `LEDR[6:3]` = adapter `debug_state`
- `LEDR[7]` = `rx_count[0]`
- `LEDR[8]` = `allow_count[0]`
- `LEDR[9]` = `drop_count[0]`

## Bring-up notes

- Keep the first hardware pass polling-based even though `INT_n` is wired.
- Verify the GPIO bank voltage and module voltage compatibility before connecting the W5500 board.
- Start with a minimal image that proves reset, SPI pin activity, and LED debug visibility before relying on live traffic.
