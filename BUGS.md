# BUGS

## Open Bugs

- Quartus timing analysis still reports the design as not fully constrained because the external W5500 timing model has not yet been turned into board-accurate I/O timing constraints. Current pre-hardware flow uses false paths for human/asynchronous inputs instead of invented external timing numbers.

---

## Resolved Bugs

- Removed Quartus SPI truncation warnings in `rtl/spi/spi_master.v` by making `CPOL` and `CPHA` explicitly 1-bit in the implementation.
- Removed the `KEY[0]` non-dedicated/global clock warning by synchronizing reset release at the DE1-SoC top-level boundary instead of using the raw pushbutton directly across the design.
- Fixed hardware reset bring-up stalling in `ST_RESET` by widening the W5500 adapter wait counter from 16 bits to 32 bits. The board-level reset delays are now large enough for real hardware and still count to completion.
- Fixed W5500 SPI read/write control-byte polarity. The original adapter treated `RWB=1` as read, but W5500 uses `RWB=0` for read and `RWB=1` for write. The hardware symptom was `VERSIONR` reading back as `0x00` even with correct wiring.
- Fixed the W5500 simulation model so it uses the same corrected SPI control-byte definitions as the hardware adapter.
- Prevented malformed or oversized W5500 RX frames from permanently locking the adapter in `ST_ERROR`; the adapter now advances the RX read pointer and commits/discards the frame.
