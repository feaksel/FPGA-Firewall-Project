# BUGS

## Open Bugs

- **B-2026-05-03-01: A-triggered W5500 B transmit does not appear on PC2.**
  - Status: open, current top hardware blocker.
  - Evidence:
    - `SW6=1` direct B transmit test works; PC2/Wireshark sees the internally generated `FW-DEMO-ALLOW-SSH` frame.
    - `SW5=1` raw A ingress debug works; A-side raw byte/commit counts rise and last frame length is around `0x50` to `0x52`.
    - Direct PC1-to-PC2 cable capture works; `wire_rawPc1traffic.pcapng` contains 18 demo frames from source MAC `00:11:22:33:44:55`.
    - `SW7=1` raw bypass does not show demo frames on PC2. Captures such as `sw7simple.pcapng` and `sw7-0004.pcapng` contain only local/background PC2 traffic, even when FPGA TX count reaches values like `0004` or `0006`.
    - `SW8=1` generated rule-demo mode was added, but the latest hardware observation was `SW[3:1]=101 = 0000`, so the generated TX path did not trigger.
  - Current interpretation:
    - W5500 A receive and W5500 B direct transmit are individually proven.
    - The unresolved failure is the A-triggered transmit path: either the rule/trigger logic does not see the expected bytes on hardware, the stream handoff is not producing the same frame bytes as expected, or the W5500 B TX adapter behaves differently when driven by A-derived events.
  - Next debug:
    - Add board-visible first-byte latches for A RX and B TX input.
    - Add deeper TX state/progress pages rather than relying only on final TX count.
    - Consider SignalTap or UART/HPS telemetry before adding more demo features.

- **B-2026-05-03-02: W5500 simulation models are not strong enough evidence for the two-port hardware path.**
  - Status: open.
  - Evidence:
    - `two_port_bypass_tb`, `de1_soc_top_bypass_tb`, and `de1_soc_top_rule_regen_tb` can pass while hardware still fails.
  - Current interpretation:
    - The models are useful for RTL syntax and high-level sequencing, but they do not yet model enough real W5500 timing, buffering, command completion, link behavior, or malformed-frame behavior to predict hardware success.
  - Next debug:
    - Strengthen models only after collecting hardware byte/state evidence, so the model changes reflect real failure modes instead of guesses.

- Quartus timing analysis still reports the design as not fully constrained because the external W5500 timing model has not yet been turned into board-accurate I/O timing constraints. Current pre-hardware flow uses false paths for human/asynchronous inputs instead of invented external timing numbers.

---

## Resolved Bugs

- Removed Quartus SPI truncation warnings in `rtl/spi/spi_master.v` by making `CPOL` and `CPHA` explicitly 1-bit in the implementation.
- Removed the `KEY[0]` non-dedicated/global clock warning by synchronizing reset release at the DE1-SoC top-level boundary instead of using the raw pushbutton directly across the design.
- Fixed hardware reset bring-up stalling in `ST_RESET` by widening the W5500 adapter wait counter from 16 bits to 32 bits. The board-level reset delays are now large enough for real hardware and still count to completion.
- Fixed W5500 SPI read/write control-byte polarity. The original adapter treated `RWB=1` as read, but W5500 uses `RWB=0` for read and `RWB=1` for write. The hardware symptom was `VERSIONR` reading back as `0x00` even with correct wiring.
- Fixed the W5500 simulation model so it uses the same corrected SPI control-byte definitions as the hardware adapter.
- Prevented malformed or oversized W5500 RX frames from permanently locking the adapter in `ST_ERROR`; the adapter now advances the RX read pointer and commits/discards the frame.
- Fixed a W5500 B TX adapter backpressure bug where normal `frame_valid && !frame_ready` conditions were treated as fatal errors.
- Changed W5500 B TX free-space handling to wait/retry instead of dropping a pending packet when `S0_TX_FSR` is temporarily too small.
- Added W5500 `S0_CR` command-clear polling after `SEND`, so TX count now represents command completion instead of merely writing the `SEND` command.
