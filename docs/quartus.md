# Quartus Build

Quartus is used to turn the RTL into the DE1-SoC programming image.

## Project Files

| File | Purpose |
| --- | --- |
| `quartus/de1_soc_w5500.qpf` | Quartus project file |
| `quartus/de1_soc_w5500.qsf` | device, source files, pins, SignalTap settings |
| `quartus/de1_soc_w5500.sdc` | timing constraint for `CLOCK_50` |
| `quartus/create_de1_soc_w5500_project.tcl` | script that recreates the project |
| `scripts/create_quartus_project.ps1` | PowerShell wrapper for the Tcl script |

The target top-level entity is:

```text
de1_soc_w5500_top
```

The target device is:

```text
5CSEMA5F31C6
```

## Refresh the Project

From the repo root:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

This recreates the project layer and points Quartus at the synthesizable RTL.

## Compile

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500
```

The expected output folder is:

```text
build/quartus/
```

Important outputs:

| Output | Use |
| --- | --- |
| `de1_soc_w5500.sof` | JTAG/SRAM programming image |
| `de1_soc_w5500.pin` | final pin assignment report |
| `de1_soc_w5500.fit.rpt` | fitter report |
| `de1_soc_w5500.sta.rpt` | timing analysis report |

## Program the Board

Connect the DE1-SoC USB-Blaster port to the PC and turn the board on. First
check that Quartus can see the cable and JTAG chain:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\jtagconfig.exe'
```

On this board the JTAG chain normally appears as:

```text
1) DE-SoC [USB-1]
  4BA00477   SOCVHPS
  02D120DD   5CSE(BA5|MA5)/5CSTFD5D5/..
```

The first device is the HPS debug TAP, so the FPGA `.sof` must be programmed
into device index 2:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_pgm.exe' -m JTAG -c 'DE-SoC [USB-1]' -o 's;SOCVHPS@1' -o 'p;build\quartus\de1_soc_w5500.sof@2'
```

Expected success message:

```text
Configuration succeeded -- 1 device(s) configured
```

This is volatile SRAM/JTAG programming. If the DE1-SoC loses power or is
reconfigured, load the `.sof` again. Do not use configuration-flash programming
for normal bench work unless the project is intentionally being made persistent.

## SignalTap

The project can use `quartus/de1_soc_w5500.stp` for SignalTap debug. The `.stp`
file and the compiled `.sof` must match. If probes are changed in SignalTap,
recompile before trusting a capture.

Capture helper scripts:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_stp.exe' -t scripts\signaltap_capture_force.tcl quartus\de1_soc_w5500.stp captures\stp\latest.csv 5
py -3 scripts\inspect_signaltap_csv.py captures\stp\latest.csv
```

## Warning Policy

Warnings that were accepted during bring-up:
- unused switch/key style warnings
- unused debug paths in some modes
- Quartus Lite license messages
- GPIO structural warnings that match the intentional tri-state pins

Warnings that should stop the flow:
- missing `.sof`
- timing failure
- SPI width/truncation issues
- `KEY[0]` being inferred as a clock
- missing W5500 GPIO assignments

Always review the `.pin` report before wiring or powering a new board setup.
