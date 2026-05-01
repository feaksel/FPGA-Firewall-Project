# Quartus Project Notes

Use this folder for the DE1-SoC Quartus project layer.

Current contents:
- `create_de1_soc_w5500_project.tcl` generates the project from the command line
- `de1_soc_w5500.sdc` provides the base `CLOCK_50` constraint

Create or refresh the project with:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

Current project scope:
- targets `de1_soc_w5500_top`
- sets the device to `5CSEMA5F31C6`
- includes the synthesizable `rtl/` files
- includes the RX FIFO path used between the adapter and firewall core
- writes Quartus outputs under `build/quartus`

Useful commands from the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa.ps1 parser_tb
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa_gui.ps1 parser_tb
```

Important:
- this project layer now includes a first DE1-SoC pin-assignment pass for `CLOCK_50`, `KEY`, `SW`, `LEDR`, and `GPIO_0`
- review the assignments against your exact board revision before hardware bring-up

Validated outputs after a successful compile:
- `build/quartus/de1_soc_w5500.sof`
- `build/quartus/de1_soc_w5500.pin`
- `build/quartus/de1_soc_w5500.fit.rpt`
- `build/quartus/de1_soc_w5500.sta.rpt`

Current accepted warning policy for pre-hardware signoff:
- okay: unused switch/key warnings, GPIO header structural warnings, Quartus Lite license warnings
- not okay: SPI truncation warnings, `KEY[0]` being treated as a clock, failing timing, or a missing `.sof`
