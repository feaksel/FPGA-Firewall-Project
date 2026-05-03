# DE1-SoC + W5500 Hardware Contract

## Board target

- FPGA board: Terasic DE1-SoC
- Ethernet module target: W5500
- Current proven wiring: one W5500 on `GPIO_0`
- Next inline wiring: second W5500 on `GPIO_1`
- Clock source: `CLOCK_50`

## Top-level module

Use [de1_soc_w5500_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/de1_soc_w5500_top.v) as the board-facing wrapper.

Control assumptions:
- `KEY[0]` = active-high board reset release for the design
- `SW[0]` = start initialization
- `SW[3:1]` = 7-segment display debug page
- `SW[4]` = LED state source select (`0` for W5500 A RX state, `1` for W5500 B TX state)
- `SW[5]` = raw W5500 A ingress drain/debug mode
- `SW[6]` = direct W5500 B generated TX self-test
- `SW[7]` = raw A-to-B bypass debug mode
- `SW[8]` = experimental generated rule-demo mode

## W5500 A / GPIO_0 wiring contract

Freeze this logical mapping for the first hardware pass:

- `GPIO_0[0]` = W5500 `SCLK`
- `GPIO_0[1]` = W5500 `MOSI`
- `GPIO_0[2]` = W5500 `CS_n`
- `GPIO_0[3]` = W5500 `RESET_n`
- `GPIO_0[4]` = W5500 `MISO`
- `GPIO_0[5]` = W5500 `INT_n`

Physical header labels:
- `GPIO_0_D0` -> W5500 A `SCLK`
- `GPIO_0_D1` -> W5500 A `MOSI`
- `GPIO_0_D2` -> W5500 A `CS_n`
- `GPIO_0_D3` -> W5500 A `RESET_n`
- `GPIO_0_D4` <- W5500 A `MISO`
- `GPIO_0_D5` <- W5500 A `INT_n`

## W5500 B / GPIO_1 wiring contract

Wire the second module with the same logical order on `GPIO_1`:

- `GPIO_1[0]` = W5500 B `SCLK`
- `GPIO_1[1]` = W5500 B `MOSI`
- `GPIO_1[2]` = W5500 B `CS_n`
- `GPIO_1[3]` = W5500 B `RESET_n`
- `GPIO_1[4]` = W5500 B `MISO`
- `GPIO_1[5]` = W5500 B `INT_n`

Physical header labels:
- `GPIO_1_D0` -> W5500 B `SCLK`
- `GPIO_1_D1` -> W5500 B `MOSI`
- `GPIO_1_D2` -> W5500 B `CS_n`
- `GPIO_1_D3` -> W5500 B `RESET_n`
- `GPIO_1_D4` <- W5500 B `MISO`
- `GPIO_1_D5` <- W5500 B `INT_n`

Quartus pins now reserved for `GPIO_1[0..5]`:
- `GPIO_1[0]` = `AB17`
- `GPIO_1[1]` = `AA21`
- `GPIO_1[2]` = `AB21`
- `GPIO_1[3]` = `AC23`
- `GPIO_1[4]` = `AD24`
- `GPIO_1[5]` = `AE23`

## UART telemetry wiring

The debug image now drives a transmit-only UART telemetry line:

- `GPIO_0[6]` / `GPIO_0_D6` = FPGA `UART_TX`

Wire this to a 3.3 V USB-UART adapter:
- FPGA `GPIO_0_D6` -> USB-UART `RX`
- FPGA/DE1-SoC ground -> USB-UART `GND`

Default serial format:
- `115200` baud
- `8N1`
- transmit-only from FPGA

Telemetry line format is compact ASCII:

```text
RX=00000000 AL=00000000 DR=00000000 RFDA.
```

Where `RX`, `AL`, and `DR` are receive/allow/drop counters, `R` is the last rule nibble, `A`/`D` is the last action, and the final character is `E` when the TX/error flag is asserted or `.` when clear.

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
- `SW[3:1] = 101`: W5500 B TX count, or direct/generated TX count depending on mode
- `SW[3:1] = 110`: last W5500 A RX size
- `SW[3:1] = 111`: last W5500 A frame length

Action display values:
- `A` = last packet was allowed
- `D` = last packet was dropped

Status nibble on page `000` is `{rx_fifo_overflow, init_error, init_done, rx_packet_seen}`.

Special mode notes:
- With `SW5=1`, forwarding is intentionally disabled. Pages show raw W5500 A receive/drain diagnostics.
- With `SW6=1`, the FPGA ignores PC1 and periodically sends a known-good internal test frame from W5500 B. This is the current proven B-side TX baseline.
- With `SW7=1`, the FPGA attempts direct raw A-to-B streaming. This currently passes simulation but fails hardware visibility on PC2.
- With `SW8=1`, the FPGA attempts to parse A-side traffic and generate a clean known-good B-side allow frame. This is experimental and currently not hardware-proven.

## Bring-up notes

- Keep the first hardware pass polling-based even though `INT_n` is wired.
- Verify the GPIO bank voltage and module voltage compatibility before connecting the W5500 board.
- Start with a minimal image that proves reset, SPI pin activity, and LED debug visibility before relying on live traffic.
- Real hardware needs millisecond-scale W5500 reset/release delays; simulation-sized waits are not enough.
- W5500 SPI control bytes use `RWB=0` for reads and `RWB=1` for writes.
- Do not connect W5500 B until the image you are programming is meant to drive `GPIO_1`; the current one-port debug image leaves `GPIO_1[5:0]` high impedance.
- `GPIO_0_D6` is no longer high impedance; it idles high as UART TX.

## Current hardware evidence

As of 2026-05-03:
- the board image programs successfully over JTAG,
- the W5500 `VERSIONR` read works on the physical module,
- W5500 A MACRAW initialization reaches RX polling,
- deterministic Scapy packets from PC1 are visible when directly cabled to PC2 and cause board W5500 A receive activity,
- W5500 B can transmit an internally generated frame to PC2 in `SW6` mode,
- A-triggered TX modes are not yet working:
  - `SW7` raw bypass produces no visible demo frames on PC2,
  - `SW8` generated rule-demo latest report showed TX count page `101 = 0000`.

Current hardware blocker:
- individual A RX and B TX paths work, but the A-triggered B TX path is not proven. Next debugging should add first-byte and TX-progress observability rather than adding more demo layers.
