# Hardware Setup

## Main Parts

- FPGA board: Terasic DE1-SoC
- Ethernet modules: two W5500 modules
- FPGA clock: `CLOCK_50`
- PC1: sender connected to W5500 A
- PC2: receiver connected to W5500 B
- Optional: 3.3 V TTL USB-UART adapter for live FPGA telemetry

The W5500 modules are controlled over SPI. W5500 A is the receive side and
W5500 B is the transmit side.

## W5500 A on GPIO_0

| DE1-SoC signal | W5500 A signal |
| --- | --- |
| `GPIO_0[0]` / `GPIO_0_D0` | `SCLK` |
| `GPIO_0[1]` / `GPIO_0_D1` | `MOSI` |
| `GPIO_0[2]` / `GPIO_0_D2` | `CS_n` |
| `GPIO_0[3]` / `GPIO_0_D3` | `RESET_n` |
| `GPIO_0[4]` / `GPIO_0_D4` | `MISO` |
| `GPIO_0[5]` / `GPIO_0_D5` | `INT_n` |
| `GPIO_0[6]` / `GPIO_0_D6` | UART TX, optional |

## W5500 B on GPIO_1

| DE1-SoC signal | W5500 B signal |
| --- | --- |
| `GPIO_1[0]` / `GPIO_1_D0` | `SCLK` |
| `GPIO_1[1]` / `GPIO_1_D1` | `MOSI` |
| `GPIO_1[2]` / `GPIO_1_D2` | `CS_n` |
| `GPIO_1[3]` / `GPIO_1_D3` | `RESET_n` |
| `GPIO_1[4]` / `GPIO_1_D4` | `MISO` |
| `GPIO_1[5]` / `GPIO_1_D5` | `INT_n` |

Quartus currently reserves `GPIO_1[0..5]` for the second W5500 module.

## Board Controls

| Control | Meaning |
| --- | --- |
| `KEY[0]` | reset release used by the design |
| `SW[0]` | start/init enable |
| `SW[3:1]` | HEX debug page select |
| `SW[4]` | normal LED state source select |
| `SW[5]` | raw W5500 A ingress drain/debug mode |
| `SW[6]` | direct W5500 B generated-frame self-test |
| `SW[7]` | legacy raw A-to-B bypass diagnostic |
| `SW[8]` | legacy generated rule-demo diagnostic |
| `SW[9]` | byte/state debug master mode |

For the normal final demo, use:

```text
SW0=1, SW5=0, SW6=0, SW7=0, SW8=0, SW9=0
```

## LEDs

| LED | Normal meaning |
| --- | --- |
| `LEDR[0]` | init done |
| `LEDR[1]` | init error |
| `LEDR[2]` | W5500 A packet seen |
| `LEDR[6:3]` | adapter debug state |
| `LEDR[7]` | low bit of receive count, or TX-side activity when `SW4=1` |
| `LEDR[8]` | stream/FIFO activity |
| `LEDR[9]` | commit/FIFO overflow depending on mode |

In `SW9=1` byte debug mode, the upper LEDs change to B-side TX progress and
error flags.

## Useful HEX Pages

In normal mode, `SW[3:1]` selects:

| Page | Meaning |
| --- | --- |
| `001` | low 16 bits of receive count |
| `010` | low 16 bits of allow count |
| `011` | low 16 bits of drop count |
| `101` | W5500 B TX count |
| `110` | last W5500 A RX size |
| `111` | last synthesized frame length |

For default file chunks, old notes recorded these useful values:
- last A RX size around `0x013A`
- synthesized frame length around `0x015C`

## Optional UART

The FPGA can transmit one telemetry line about every half second.

Wire a 3.3 V TTL USB-UART adapter like this:

```text
GPIO_0_D6 -> USB-UART RX
GND       -> USB-UART GND
```

Use `115200 8N1`, no flow control. Do not connect the adapter 5 V pin, and do
not use RS-232 voltage levels.

The PC2 rule dashboard can read it with:

```powershell
py -3 scripts\rule_demo_receiver_dashboard.py --iface Ethernet --uart COM7 --port 8091
```

Replace `COM7` with the port shown by Windows Device Manager.
