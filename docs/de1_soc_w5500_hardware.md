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
- `SW[3:1]` = 7-segment display debug page

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

## 7-segment debug pages

The board image drives `HEX3..HEX0` as active-low common-anode displays.

- `SW[3:1] = 000`: `adapter_state`, `last_rule_id`, `A`/`D` action, status bits
- `SW[3:1] = 001`: low 16 bits of `rx_count`
- `SW[3:1] = 010`: low 16 bits of `allow_count`
- `SW[3:1] = 011`: low 16 bits of `drop_count`
- `SW[3:1] = 100`: last rule, last action, FIFO overflow marker, packet/error marker

Action display values:
- `A` = last packet was allowed
- `D` = last packet was dropped

Status nibble on page `000` is `{rx_fifo_overflow, init_error, init_done, rx_packet_seen}`.

## Bring-up notes

- Keep the first hardware pass polling-based even though `INT_n` is wired.
- Verify the GPIO bank voltage and module voltage compatibility before connecting the W5500 board.
- Start with a minimal image that proves reset, SPI pin activity, and LED debug visibility before relying on live traffic.
- On the DE1-SoC GPIO header, the intended physical mapping is `GPIO_0_D0` through `GPIO_0_D5`:
  - `GPIO_0_D0` -> W5500 `SCLK`
  - `GPIO_0_D1` -> W5500 `MOSI`
  - `GPIO_0_D2` -> W5500 `CS_n`
  - `GPIO_0_D3` -> W5500 `RESET_n`
  - `GPIO_0_D4` <- W5500 `MISO`
  - `GPIO_0_D5` <- W5500 `INT_n`
- Real hardware needs millisecond-scale W5500 reset/release delays; simulation-sized waits are not enough.
- W5500 SPI control bytes use `RWB=0` for reads and `RWB=1` for writes.

## Current hardware evidence

As of 2026-05-01:
- the board image programs successfully over JTAG,
- the W5500 `VERSIONR` read works on the physical module,
- MACRAW initialization reaches RX polling,
- deterministic Scapy packets from the PC are visible in Wireshark and cause board receive/counter activity,
- the board image includes HEX display pages for readable RX/allow/drop counters and last-rule/last-action state.
