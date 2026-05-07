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
- `SW[9]` = byte/state debug master mode

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

The final UDP policy gateway image drives a transmit-only UART telemetry line:

- `GPIO_0[6]` / `GPIO_0_D6` = FPGA `UART_TX`
- Quartus location: `PIN_AK19`
- I/O standard: `3.3-V LVTTL`

Wire this to a **3.3 V TTL USB-UART adapter**:
- FPGA `GPIO_0_D6` -> USB-UART `RX`
- FPGA/DE1-SoC ground -> USB-UART `GND`

Do not connect the USB-UART adapter's `5V` pin to the board. Do not use an
old RS-232 serial cable; RS-232 voltage levels are not compatible with the
FPGA GPIO header. The adapter's `TXD` pin is optional and is not used by the
current design because telemetry is transmit-only from FPGA to PC.

Default serial format:
- `115200` baud
- `8N1`
- no flow control
- transmit-only from FPGA

On Windows, plug in the USB-UART adapter and check Device Manager under
`Ports (COM & LPT)` for the assigned port, for example `COM7`. The PC2
dashboard reads the line stream with:

```powershell
py -3 scripts\rule_demo_receiver_dashboard.py --iface Ethernet --uart COM7 --port 8091
```

For a direct sanity check before starting the dashboard, open the COM port in
PuTTY, TeraTerm, or `pyserial`'s miniterm at `115200 8N1`. The FPGA should print
one compact ASCII telemetry line roughly every `0.5 s`.

Current telemetry line format:

```text
RX=00000010 AL=00000008 DR=00000002 R=0A. U80=00000004 U51=00000004 D52=00000002 SIG=00000001 DEF=00000000 FIL=00000003 SIN=00000000
```

Field meanings:
- `RX`: FPGA receive counter.
- `AL`: aggregate allowed counter.
- `DR`: aggregate dropped counter.
- `R=<rule><action><status>`: last rule nibble, `A`/`D` action, and `E`/`.` status.
- `U80`: UDP/80 allow hits.
- `U51`: UDP/5001 allow hits.
- `D52`: UDP/5002 drop hits.
- `SIG`: payload-signature block hits (`FW-BLOCK` / `FW-DEMO-DROP`).
- `DEF`: default-drop hits.
- `FIL`: file marker hits (`FWFILE1\0`).
- `SIN`: sine marker hits (`FWSINE2\0`).

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

Normal mode (`SW9=0`):
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

Byte/state debug mode (`SW9=1`):
- `SW5=0, SW4=0`: first 16 committed bytes from W5500 A RX, two bytes per page.
- `SW5=0, SW4=1`: first 16 committed bytes handed into W5500 B TX, two bytes per page.
- `SW5=1, SW4=0`: W5500 B TX progress pages:
  - `000`: sticky flags and init/error bits
  - `001`: B TX adapter state plus A RX adapter state
  - `010`: TX-buffer write-start count
  - `011`: SEND-issued count
  - `100`: SEND-cleared count
  - `101`: SEND-timeout count
  - `110`: W5500 B TX count
  - `111`: W5500 B last packet length
- `SW5=1, SW4=1`: SW8 rule-regen parser pages:
  - `000`: ethertype
  - `001`: IP protocol
  - `010`: destination port
  - `011`: generated allow count
  - `100`: generated drop count
  - `101`: frames seen
  - `110`: last EOP byte index
  - `111`: max byte index

In `SW9=1` mode, `LEDR[6:3]` changes from adapter-state display to sticky B TX
progress flags: `{timeout, send_cleared, send_issued, buf_write}`. `LEDR7`
means the B TX input stream saw an EOP, `LEDR8` means B has a packet pending,
and `LEDR9` means B TX error.

Special mode notes:
- With `SW5=1`, forwarding is intentionally disabled. Pages show raw W5500 A receive/drain diagnostics.
- With `SW6=1`, the FPGA ignores PC1 and periodically sends a known-good internal test frame from W5500 B. This is the current proven B-side TX baseline.
- With `SW7=1`, the FPGA attempts direct raw A-to-B streaming. This is retained as a legacy MACRAW diagnostic mode.
- With `SW8=1`, the FPGA attempts to parse A-side traffic and generate a clean known-good B-side allow frame. This is retained as a legacy debug mode; the final demo uses W5500 A UDP socket ingress.

## Bring-up notes

- Keep the first hardware pass polling-based even though `INT_n` is wired.
- Verify the GPIO bank voltage and module voltage compatibility before connecting the W5500 board.
- Start with a minimal image that proves reset, SPI pin activity, and LED debug visibility before relying on live traffic.
- Real hardware needs millisecond-scale W5500 reset/release delays; simulation-sized waits are not enough.
- W5500 SPI control bytes use `RWB=0` for reads and `RWB=1` for writes.
- Do not connect W5500 B until the image you are programming is meant to drive `GPIO_1`; the current one-port debug image leaves `GPIO_1[5:0]` high impedance.
- `GPIO_0_D6` is no longer high impedance; it idles high as UART TX.

## Current hardware evidence

As of 2026-05-07:
- the board image programs successfully over JTAG,
- the W5500 `VERSIONR` read works on the physical modules,
- W5500 A UDP sockets open and receive PC1 traffic,
- W5500 B can transmit an internally generated frame to PC2 in `SW6` mode,
- W5500 B can transmit PC1-triggered UDP/80 and UDP/5001 policy-forwarded frames to PC2,
- SignalTap after the forwarder byte-index fix showed `last_frame_len=b_last_pkt_len=0x015C`, `b_tx_count=0x7D`, and `b_send_timeouts=0` for UDP/5001 file chunks,
- PC2 Npcap sniff captured UDP/5001 `FWFILE1\0` chunks with 306-byte payloads.

Current hardware focus:
- complete the safe-rate file SHA-256 proof,
- prove UDP/5002 and content-block drops without PC2 leaks,
- use UART histograms when a 3.3 V TTL USB-UART adapter is available; otherwise use HEX pages and SignalTap over USB-Blaster.
