# SignalTap II Logic Analyzer for the Two-Port Firewall

This is the practical guide for using the **DE1-SoC's USB-Blaster JTAG link** to capture
in-fabric waveforms while the W5500 firewall is running on hardware. SignalTap II
is the in-Quartus equivalent of plugging a logic analyzer onto the FPGA, except
the probe lives inside the FPGA fabric and the wires come out over the same JTAG
cable Quartus already uses to program the board.

## Why this is the right tool for the current bug

The current open hardware blocker (B-2026-05-03-01) is "A-triggered W5500 B
transmit does not appear on PC2." HEX pages on the board now show the *first 16
bytes* of A RX and B TX input plus B TX progress flags (see
[SW9 byte/state debug mode](#sw9-quick-reference) below). That tells us *what* the
chip saw and *which sub-state* it reached. SignalTap goes further: it captures
the full byte stream and the SPI lines cycle-accurately around a trigger event
like `frame_eop` or `tx_error_b`, so we can see *how* a bad byte arrived or *why*
SEND completed but PC2 saw nothing.

Use the HEX pages first. Use SignalTap when the HEX pages have narrowed the
question to "what exactly happened in the window of N clocks around event X?"

## Hardware required

- DE1-SoC programmed with the firewall image (any recent `de1_soc_w5500.sof`).
- USB-Blaster cable from the DE1-SoC's `USB BLASTER` port (USB-B) to the PC.
  - PC side: USB-A on most laptops. If the PC has only USB-C, use a
    USB-C-to-USB-B cable, or a USB-C-to-USB-A adapter plus your existing cable.
  - The two other USB ports on the DE1-SoC (USB OTG, USB HOST) go to the HPS
    Linux side and are *not* used for fabric debug.
- Quartus Prime Lite 25.1std (already installed at
  `C:\altera_lite\25.1std\quartus`).

## One-time setup

The first time you add SignalTap to this project, you do this in the Quartus
GUI. Subsequent runs are just "Run Analyzer" and (optionally) recompile if the
RTL changed.

1. Open Quartus Prime, then `File -> Open Project ->`
   `C:\Users\furka\Projects\ELE432_ethernet\quartus\de1_soc_w5500.qpf`.
2. `Tools -> SignalTap II Logic Analyzer`.
3. In the SignalTap window: `File -> Save As ->`
   `C:\Users\furka\Projects\ELE432_ethernet\quartus\de1_soc_w5500.stp`.
4. When prompted, accept "Add file to project" and "Use as the SignalTap II
   File for the project (`SLD_NODE_ENTITY_HIERARCHY` etc.)". Quartus will add
   `set_global_assignment -name SIGNALTAP_FILE de1_soc_w5500.stp` and
   `ENABLE_SIGNALTAP ON` to the QSF for you.
5. In the SignalTap "Instance Manager" the default instance is fine. Set:
   - `Clock`: pick `CLOCK_50` (or `u_w5500_b_tx|clk`, which is the same net).
   - `Sample depth`: `2K` is plenty for one frame and a couple of SEND cycles.
   - `Storage qualifier`: leave `Continuous` for the first run.
6. In the "Setup" tab, click "double-click to add nodes". A "Node Finder"
   opens.
   - Filter: `SignalTap II: pre-synthesis`.
   - Click `List`, then drag in the recommended signal set (next section).
7. In the Trigger column, set the trigger condition (next section).
8. `File -> Save` to write the `.stp`.
9. `Processing -> Start Compilation` (full Quartus compile re-runs).
   - The compile is the same flow you already use; SignalTap just instruments
     the design.

## SW9 quick reference

`SW9=1` turns the board into byte/state debug mode. In this mode `SW[5:4]`
selects the debug bank and `SW[3:1]` selects the page inside that bank.

| Switches | Meaning on `HEX3..HEX0` |
| --- | --- |
| `SW9=1, SW5=0, SW4=0` | First 16 committed bytes from W5500 A RX, two bytes per page. Page `000` shows bytes 0-1, page `001` shows bytes 2-3, and so on. |
| `SW9=1, SW5=0, SW4=1` | First 16 committed bytes handed into W5500 B TX, same two-bytes-per-page layout. |
| `SW9=1, SW5=1, SW4=0` | W5500 B TX progress pages: flags, A/B states, TX-buffer write count, SEND issued count, SEND cleared count, timeout count, TX count, last packet length. |
| `SW9=1, SW5=1, SW4=1` | SW8 rule-regen parser pages: ethertype, IP protocol, destination port, allow/drop counts, frames seen, last EOP byte index, max byte index. |

In `SW9=1` mode, `LEDR[6:3]` shows sticky B TX progress flags:
`timeout, send_cleared, send_issued, buf_write`. `LEDR7` means B saw an EOP
on its input stream, `LEDR8` means the B TX adapter has a packet pending, and
`LEDR9` means B TX error.

## Easy probe set

The top-level now exposes preserved SignalTap-friendly aliases. In Node Finder,
search for:

```text
*stp*
```

Add these first:

- `stp_rx_data[7..0]`
- `stp_rx_ctrl[4..0]`
- `stp_tx_b_data[7..0]`
- `stp_tx_b_ctrl[4..0]`
- `stp_adapter_b_state[4..0]`
- `stp_adapter_a_state[3..0]`
- `stp_b_buf_writes[31..0]`
- `stp_b_send_issued[31..0]`
- `stp_b_send_cleared[31..0]`
- `stp_b_send_timeouts[31..0]`
- `stp_b_tx_count[31..0]`
- `stp_b_last_pkt_len[15..0]`
- `stp_b_status[7..0]`
- `stp_spi_b[3..0]`
- `stp_switches[9..0]`
- `stp_a_rx_first16[127..0]`
- `stp_b_tx_first16[127..0]`
- `stp_regen_ethertype[15..0]`
- `stp_regen_ip_proto[7..0]`
- `stp_regen_dst_port[15..0]`

The packed control buses are:

- `stp_rx_ctrl = {rx_frame_valid, rx_frame_ready, rx_frame_sop, rx_frame_eop, rx_packet_seen_a}`
- `stp_tx_b_ctrl = {tx_to_b_valid, tx_frame_ready, tx_to_b_sop, tx_to_b_eop, b_pkt_available}`
- `stp_b_status = {tx_error_b, timeout_seen, send_cleared_seen, send_issued_seen, buf_write_seen, b_eop_seen, b_pkt_available, init_error_b}`
- `stp_spi_b = {spi_b_cs_n, spi_b_sclk, spi_b_mosi, spi_b_miso}`

For first debug, trigger on `stp_tx_b_ctrl[1] = 1`, which is B TX input EOP,
or on `stp_b_send_issued[0]` rising.

## How to set a trigger

In the SignalTap `Setup` tab, every probe row has trigger cells to the right of
the signal name. Use one simple trigger at a time.

To trigger when a bit is `1`:

1. Expand the bus with the small `+`.
2. Find the bit, for example `stp_tx_b_ctrl[1]`.
3. Click the trigger cell on that bit's row.
4. Type or select `1`.
5. Make sure other trigger cells are blank or `X` unless you intentionally want
   a multi-signal trigger.

To trigger on a rising edge:

1. Expand the bus and find the bit, for example `stp_b_send_issued[0]`.
2. Click the trigger cell on that bit's row.
3. Right-click the trigger cell and choose `Rising Edge`, or use the small edge
   icon/dropdown in the trigger cell if Quartus shows it.
4. The cell should show an edge/rise marker instead of a plain `1`.

If the GUI does not offer edge mode on a bus bit, use a level trigger instead:
trigger on `stp_b_send_issued[0] = 1`, click `Run Analysis`, then reset/restart
the FPGA or start traffic after the analyzer is armed. For our debug work this
is usually good enough.

Recommended trigger order:

1. `stp_tx_b_ctrl[1] = 1` to catch B TX input EOP.
2. `stp_b_send_issued[0]` rising, or `stp_b_send_issued[0] = 1`, to catch the
   first W5500 B SEND command.
3. `stp_b_send_timeouts[0] = 1` only if the timeout count rises.

## Original signal set for the A-to-B handoff bug

Drag these into the SignalTap node list. Names match the RTL.

**Top-level handshakes**
- `de1_soc_w5500_top|rx_frame_valid`
- `de1_soc_w5500_top|rx_frame_ready`
- `de1_soc_w5500_top|rx_frame_data[7..0]`
- `de1_soc_w5500_top|rx_frame_sop`
- `de1_soc_w5500_top|rx_frame_eop`
- `de1_soc_w5500_top|tx_to_b_valid`
- `de1_soc_w5500_top|tx_frame_ready`
- `de1_soc_w5500_top|tx_to_b_data[7..0]`
- `de1_soc_w5500_top|tx_to_b_sop`
- `de1_soc_w5500_top|tx_to_b_eop`

**Adapter states and progress**
- `de1_soc_w5500_top|adapter_a_debug_state[3..0]`
- `de1_soc_w5500_top|adapter_b_debug_state[4..0]`
- `de1_soc_w5500_top|b_pkt_available`
- `de1_soc_w5500_top|tx_error_b`
- `de1_soc_w5500_top|b_buf_write_start_count[3..0]`
- `de1_soc_w5500_top|b_send_issued_count[3..0]`
- `de1_soc_w5500_top|b_send_cleared_count[3..0]`
- `de1_soc_w5500_top|b_send_timeout_count[3..0]`

**SPI to W5500 B (so you can see what was actually shifted out)**
- `de1_soc_w5500_top|spi_b_sclk`
- `de1_soc_w5500_top|spi_b_mosi`
- `de1_soc_w5500_top|spi_b_miso`
- `de1_soc_w5500_top|spi_b_cs_n`

**Regen FSM (only useful in SW8 mode)**
- `de1_soc_w5500_top|regen_byte_index[15..0]`
- `de1_soc_w5500_top|regen_ethertype[15..0]`
- `de1_soc_w5500_top|regen_ip_proto[7..0]`
- `de1_soc_w5500_top|regen_dst_port[15..0]`
- `de1_soc_w5500_top|regen_allow_pending`

## Trigger conditions to start with

Pick *one* per session.

- "First B SEND attempt": trigger when `b_send_issued_count` rises from 0 to 1.
  Setup: trigger column = `0...01` (rising edge of bit 0 of the count).
  This shows the full sequence around the first SEND.
- "B TX error": trigger when `tx_error_b` goes high. Catches the SEND-timeout path.
- "First A EOP": trigger on `rx_frame_eop && rx_frame_ready` (use a basic AND
  trigger). Lets you see what the *last byte* of an A-side frame looked like
  and whether B started accepting bytes immediately after.
- "B accepted a frame": trigger on `tx_to_b_eop && tx_frame_ready`. Shows
  exactly what B received as the final byte of a forwarded frame.

For most cases of the current bug, "First B SEND attempt" with sample depth 2K
is the most informative.

## 2026-05-03 first useful capture

The first SignalTap capture with `SW7=1` showed:

- `stp_switches = 0x081`, so `SW0=1` and `SW7=1`.
- `stp_b_buf_writes = 1`.
- `stp_b_send_issued = 1`.
- `stp_b_send_cleared = 1`.
- `stp_b_send_timeouts = 0`.
- `stp_b_tx_count = 1`.
- `stp_b_last_pkt_len = 0x004E`.
- `stp_adapter_b_state = 0x06`, ready state.
- `stp_b_tx_first16 = FFFFFFFFFFFF00112233445508004500`.

Interpretation: SW7 is no longer a total FPGA handoff failure. The FPGA handed
a valid-looking Ethernet/IPv4 frame to W5500 B TX, the TX adapter wrote the TX
buffer, issued SEND, and the W5500 cleared SEND without timeout. The remaining
bug is now downstream of this proof point: PC2 capture/filtering, W5500 B
physical/link behavior, later-frame corruption after byte 16, or a one-packet
then stall condition.

## 2026-05-03 SEND-window capture

A later capture triggered around the first SEND attempt showed:

- `stp_switches = 0x083`, so `SW0=1`, `SW1=1`, and `SW7=1`.
- `stp_adapter_b_state` moved from `0x0E` (`ST_SEND`) to `0x10`
  (`ST_WAIT_SEND`).
- `stp_b_buf_writes = 1`.
- `stp_b_send_issued` rose from `0` to `1`.
- `stp_b_send_cleared = 0` inside the shown window.
- `stp_b_send_timeouts = 0`.
- `stp_b_tx_count = 0` inside the shown window.
- `stp_b_last_pkt_len = 0x0070`.
- `stp_spi_b` showed active SPI traffic while waiting for SEND to clear.

Interpretation: the capture hit the exact SEND issue window, but the 2K sample
depth is too short to also show the command-clear result. For the next capture,
either increase sample depth to `8K` or `16K`, or trigger directly on
`stp_b_send_cleared[0] = 1`.

## 2026-05-03 CLI capture and pcap comparison

A command-line capture exported through `scripts/signaltap_capture.tcl` and
summarized with `scripts/inspect_signaltap_csv.py` showed:

- `stp_switches = 0x083`, so `SW0=1`, `SW1=1`, and `SW7=1`.
- `stp_b_buf_writes = 3`.
- `stp_b_send_issued = 3`.
- `stp_b_send_cleared = 3`.
- `stp_b_send_timeouts = 0`.
- `stp_b_tx_count = 3`.
- `stp_b_last_pkt_len = 0x00F3`.
- `stp_a_rx_first16 = 3333000000FB1CF64C44FF4686DD6008`.
- `stp_b_tx_first16 = 3333000000FB1CF64C44FF4686DD6008`.

The available PC2 capture `sw7-0004.pcapng` contains three frames from the Mac
source MAC `1c:f6:4c:44:ff:46` to multicast destinations, matching the
SignalTap A/B first-byte evidence. That means `SW7` raw A-to-B forwarding is no
longer considered totally dead: at least some Mac-origin frames make it through
W5500 A, FPGA, W5500 B, and into PC2 Wireshark.

The remaining rule-demo failure is now narrower: the older sender used a
spoofed Ethernet source MAC `00:11:22:33:44:55`. Because real Mac-origin
background frames were forwarded while the spoofed demo markers were absent,
the PC1 demo senders now default to the selected interface's real MAC address.
The rule-demo sender also defaults to destination MAC `01:00:5e:00:00:fb`,
matching the multicast path that hardware has already proven. Use
`--src-mac ...` only when intentionally testing spoofed-source traffic.

## 2026-05-04 SW7=0 normal firewall capture

With `SW7=0` and `SW0=1`, command-line SignalTap showed:

- `stp_switches = 0x003`, so `SW0=1`, `SW1=1`, and `SW7=0`.
- `stp_b_buf_writes = 4`.
- `stp_b_send_issued = 4`.
- `stp_b_send_cleared = 4`.
- `stp_b_send_timeouts = 0`.
- `stp_b_tx_count = 4`.
- `stp_a_rx_first16 = 01005E0000FB1CF64C44FF4608004500`.
- `stp_b_tx_first16 = 01005E0000FB1CF64C44FF4608004500`.

Interpretation: the normal firewall path is not stuck at the B TX boundary.
It forwarded an IPv4 multicast frame from the Mac through W5500 B. The dashboard
did not update because the captured forwarded frame was background mDNS traffic,
not a `FW-DEMO-*` marker. The next retest should use the updated
multicast/real-MAC rule-demo sender.

## Command-line SignalTap note

Quartus does include command-line SignalTap tools:

```text
C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe
C:\altera_lite\25.1std\quartus\bin64\quartus_stp_tcl.exe
```

The executable exposes a Tcl acquisition package (`::quartus::stp`). This means
we can script capture/run/export instead of relying only on GUI screenshots.

The repo includes a wrapper:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' `
  -t scripts\signaltap_capture.tcl `
  quartus\de1_soc_w5500.stp `
  captures\stp\latest.csv `
  20
```

The wrapper auto-detects the generated SignalTap instance, signal-set, and
trigger names from `quartus/de1_soc_w5500.stp`. If Quartus changes the names
again after a GUI edit, the same command should still work. The wrapper ignores
Quartus's internal `auto_stp_external_storage_qualifier` name, which is not a
valid trigger.

Then summarize the exported CSV:

```powershell
py -3 scripts\inspect_signaltap_csv.py captures\stp\latest.csv
```

For Wireshark/pcap comparison, summarize Ethernet sources, ethertypes, ports,
and demo markers with:

```powershell
py -3 scripts\pcap_summary.py C:\Users\furka\Desktop\sw7-0004.pcapng
```

If the command reports `JTAG chain in use`, close the SignalTap GUI capture
window or stop the GUI analyzer before retrying.

## Capture flow

After the .stp is added and Quartus has recompiled:

1. Re-program the board with the new `.sof` (it includes SignalTap).
2. In the SignalTap window, set "Hardware: USB-Blaster" (top right) and click
   `Setup`. The device chain should show `5CSEMA5` etc.
3. Set the SOF: it should auto-pick `build/quartus/de1_soc_w5500.sof`. If not,
   use the dropdown to select it.
4. Click "Run Analysis" (the small play icon).
5. Trigger the condition you set (e.g., flip switches, send PC1 traffic).
6. The waveform appears in the Data tab. Save the capture with
   `File -> Save Captured Data` for the bug log.

## Tips

- SignalTap costs FPGA RAM (M9K) blocks proportional to `sample_depth *
  total_signal_width`. The recommended set above is well under 1 BRAM.
- If your trigger never fires, set "Continuous" mode and re-run; you'll see
  whatever the last 2K samples were when you stopped.
- "Storage qualifier" with a clock-enable signal lets you skip idle cycles. For
  this bug, idle is short (50 MHz clock, frames in tens of microseconds), so
  continuous mode is fine.
- The `.stp` file is now part of the project (`ENABLE_SIGNALTAP ON`). To ship a
  release `.sof` without the SignalTap probe, set
  `ENABLE_SIGNALTAP OFF` in the QSF and recompile.

## Out-of-scope alternatives

These are also possible over the same USB-Blaster link, but heavier:

- **JTAG UART** via Qsys: gives a console terminal over JTAG. Useful for ASCII
  prints during runtime. Requires adding a Qsys system and a
  `nios2-terminal`-style host program. Defer.
- **System Console + Avalon-MM**: Tcl host that reads/writes on-chip registers
  through a JTAG-to-Avalon bridge. Requires more Qsys glue. Defer.
- **HPS-side debug** (USB OTG / USB HOST ports): runs Linux on the ARM core,
  bridges into the fabric via the FPGA-to-HPS bus. Out of scope for this
  project's current MVP.

For the current bug the SignalTap path above gets us answers in under an
hour of bench time and does not require any new tooling.
