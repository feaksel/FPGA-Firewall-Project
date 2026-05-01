# BUGS

## Open Bugs

- Quartus timing analysis still reports the design as not fully constrained because the external W5500 timing model has not yet been turned into board-accurate I/O timing constraints. Current pre-hardware flow uses false paths for human/asynchronous inputs instead of invented external timing numbers.

---

## Resolved Bugs

- Removed Quartus SPI truncation warnings in `rtl/spi/spi_master.v` by making `CPOL` and `CPHA` explicitly 1-bit in the implementation.
- Removed the `KEY[0]` non-dedicated/global clock warning by synchronizing reset release at the DE1-SoC top-level boundary instead of using the raw pushbutton directly across the design.
