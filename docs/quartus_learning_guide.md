# Quartus Learning Guide

## Goal

This guide explains the Quartus project files and workflow used in this repo in plain language.

It is written around the current DE1-SoC project, so each concept is tied to a real file in this repository instead of staying abstract.

## Big picture

Quartus is the FPGA toolchain that takes your RTL and turns it into something the FPGA on the DE1-SoC board can run.

At a high level, the flow is:
1. describe the hardware in Verilog
2. tell Quartus which FPGA device and board pins you are targeting
3. compile the design
4. generate a programming file
5. load that file into the FPGA

For this project, that means:
1. the design lives under `rtl/`
2. the Quartus project lives under `quartus/`
3. compile outputs go under `build/quartus/`
4. the FPGA is programmed with a `.sof` file

## The key Quartus files in this repo

### `quartus/de1_soc_w5500.qpf`

This is the Quartus Project File.

Think of it as the small file that tells Quartus:
- this project exists
- this is its name
- this is the active revision

In our case, it points to the project revision:
- `de1_soc_w5500`

You can think of the `.qpf` as the file you open first in the Quartus GUI.

### `quartus/de1_soc_w5500.qsf`

This is the Quartus Settings File.

This is the important project configuration file.

It tells Quartus things like:
- which FPGA device is being targeted
- which module is the top-level design
- which RTL files belong to the project
- which board pins are assigned to which signals
- which I/O standard each pin uses
- where Quartus should write the build output

Examples from this repo:
- device: `5CSEMA5F31C6`
- top-level entity: `de1_soc_w5500_top`
- output directory: `../build/quartus`

This file is where most hardware-project setup lives.

### `quartus/de1_soc_w5500.sdc`

This is the Synopsys Design Constraints file.

Its main job is to tell Quartus about timing.

Right now, it contains the base clock constraint:

```tcl
create_clock -name {CLOCK_50} -period 20.000 [get_ports {CLOCK_50}]
```

That means:
- the signal `CLOCK_50` is a clock
- its period is `20 ns`
- which corresponds to `50 MHz`

Quartus uses this to check timing and decide whether the design can run reliably at that clock speed.

### `quartus/create_de1_soc_w5500_project.tcl`

This is the project generator script.

Instead of building the Quartus project by hand in the GUI, this script creates or refreshes the project from the terminal.

That is useful because:
- it is repeatable
- it reduces setup mistakes
- it lets us recreate the project quickly
- it keeps the project structure understandable

### `scripts/create_quartus_project.ps1`

This PowerShell helper runs the Quartus TCL script for you.

This is the easiest command to recreate the project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

## The top-level design in this project

The Quartus project does not synthesize every file in the repo. It synthesizes the hardware design starting from one top-level module.

That top-level module is:
- [de1_soc_w5500_top.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/top/de1_soc_w5500_top.v)

This file is the board-facing wrapper.

It connects the DE1-SoC board resources:
- `CLOCK_50`
- `KEY`
- `SW`
- `LEDR`
- `GPIO_0`

to the actual firewall design underneath.

So when Quartus asks “what is the hardware design I should compile?”, the answer is:
- top-level entity = `de1_soc_w5500_top`

## The important Quartus settings in this project

### Device selection

The project targets this FPGA:
- `5CSEMA5F31C6`

That is the Cyclone V SoC FPGA on the DE1-SoC board.

If the wrong device is selected, compilation may still start, but the bitstream will not match the real board.

### Source files

The `.qsf` lists the synthesizable RTL files, including:
- `rtl/top/de1_soc_w5500_top.v`
- `rtl/top/firewall_top.v`
- `rtl/eth_if/ethernet_controller_adapter.v`
- `rtl/firewall/firewall_core.v`
- `rtl/parser/eth_ipv4_parser.v`
- `rtl/rules/rule_engine.v`
- `rtl/spi/spi_master.v`
- `rtl/buffer/packet_buffer.v`
- `rtl/debug/debug_counters.v`

Notice what is not included:
- testbenches in `tb/`

Quartus is for synthesis and implementation, not simulation testbench execution.

### Pin assignments

The `.qsf` also maps logical signals to real FPGA package pins.

For example:
- `CLOCK_50` is assigned to a real DE1-SoC pin
- `LEDR[0]` through `LEDR[9]` are assigned to the board LEDs
- `KEY[0]` through `KEY[3]` are assigned to the pushbuttons
- `GPIO_0[x]` is assigned to the expansion header pins

This is what makes the design interact with the physical board instead of staying a simulation-only project.

### I/O standards

Each external signal also gets an I/O standard assignment such as:
- `3.3-V LVTTL`

That tells Quartus what voltage/signaling level the external pins are expected to use.

For the DE1-SoC GPIO header and the W5500 SPI/control signals, that matches the intended `3.3 V` interface.

## What compile means in Quartus

When you click compile, Quartus does not do one single mysterious step. It runs several major stages.

### 1. Analysis & Synthesis

This stage:
- reads your Verilog
- checks the module hierarchy
- elaborates the design
- turns RTL into FPGA logic structures

This is the stage where syntax problems, missing modules, and many structural issues are caught.

### 2. Fitter

This stage:
- places the logic into actual FPGA resources
- routes the connections between them
- applies board pin assignments

This is where the abstract logic becomes a real implementation for the selected FPGA chip.

### 3. Assembler

This stage:
- produces the programming file

For normal FPGA SRAM programming, the important output is:
- `.sof`

In this repo, the generated file is:
- [de1_soc_w5500.sof](/c:/Users/furka/Projects/ELE432_ethernet/build/quartus/de1_soc_w5500.sof)

### 4. Timing Analyzer

This stage:
- checks whether the final routed hardware meets the clock timing constraints from the `.sdc`

If timing fails, the design may still compile, but it may not run reliably at the target clock rate.

## What the main build outputs mean

The build outputs are under:
- `build/quartus/`

Important files there:

### `.sof`

This is the SRAM Object File.

This is the file you use to program the FPGA over JTAG for immediate testing.

It is:
- fast to use
- ideal during development
- not persistent after power-off

### `.fit.rpt`

This is the fitter report.

It tells you about placement, routing, pin usage, and fitter warnings.

### `.sta.rpt`

This is the timing report.

It tells you whether your timing constraints were met.

### `.map.rpt`

This is the analysis/synthesis report.

It tells you about logic usage, synthesis warnings, and how Quartus understood the RTL.

### `.pin`

This is a generated pin report.

It is a nice way to verify what signal ended up on what FPGA package pin.

## What programming means

Programming is different from compiling.

Compiling:
- creates the FPGA configuration file

Programming:
- sends that file into the board

So the flow is:
1. compile the project
2. get the `.sof`
3. send the `.sof` to the DE1-SoC over USB-Blaster/JTAG

## What happens when you open the `.qpf`

When you open:
- [de1_soc_w5500.qpf](/c:/Users/furka/Projects/ELE432_ethernet/quartus/de1_soc_w5500.qpf)

in the Quartus GUI, Quartus loads the project and then uses:
- the `.qsf` for project settings and pins
- the `.sdc` for timing constraints

After that, you can:
- inspect files
- compile
- open reports
- open the Programmer
- load the `.sof` onto the board

## The normal GUI flow you will use

### Step 1: Open the project

Open:
- [de1_soc_w5500.qpf](/c:/Users/furka/Projects/ELE432_ethernet/quartus/de1_soc_w5500.qpf)

### Step 2: Check the top-level and files

In Quartus, make sure:
- the top-level entity is `de1_soc_w5500_top`
- the RTL files are present

### Step 3: Compile

Use:
- `Processing -> Start Compilation`

This regenerates the implementation and the `.sof`.

### Step 4: Open the Programmer

Use:
- `Tools -> Programmer`

Then:
- select the `USB-Blaster`
- add the `.sof` if it is not already listed
- check `Program/Configure`
- click `Start`

### Step 5: Observe the board

After programming:
- the FPGA is configured
- the LEDs should reflect the design state
- `SW[0]` and `KEY[0]` affect the design behavior

## JTAG programming vs persistent configuration

For now, use JTAG programming with the `.sof`.

Why:
- it is the fastest for development
- it is easy to reprogram repeatedly
- it avoids extra flash-programming complexity while the design is still changing

Important:
- `.sof` programming does not survive power cycling

That means if you turn the board off, you need to program it again.

## Why some warnings still exist

The current project compiles successfully, but Quartus still reports some warnings. That is normal during development.

### Unused switch and key warnings

Some inputs such as `KEY[1:3]` and `SW[1:9]` are not used by the design yet.

That is not a problem by itself.

### GPIO tri-state warnings

The GPIO header is declared as `inout`, because the board header is physically bidirectional.

In our top-level:
- some pins are true outputs
- some are read as inputs
- the unused ones are parked at high-Z

Quartus warns about that style, but it still compiled and fitted successfully.

### Incomplete constraints warning

The design currently has a base clock constraint for `CLOCK_50`, but not every possible path has a detailed timing constraint yet.

That is common in an early project phase.

### Width-truncation warnings in `spi_master.v`

Quartus warned about a few assignments in:
- [spi_master.v](/c:/Users/furka/Projects/ELE432_ethernet/rtl/spi/spi_master.v)

These are worth cleaning up later, but they did not stop compile or fitting.

## What `db/` and `incremental_db/` are

Inside `quartus/`, Quartus also creates folders like:
- `db/`
- `incremental_db/`

These are internal project databases used by Quartus for compilation bookkeeping.

You usually do not edit these manually.

They are not where your design intent lives.

Your design intent lives mainly in:
- RTL files under `rtl/`
- project settings in `.qsf`
- timing constraints in `.sdc`

## What you should learn to recognize first

When looking at a Quartus project, the most important beginner concepts are:

### 1. Top-level entity

This answers:
- which module represents the whole board design?

For us:
- `de1_soc_w5500_top`

### 2. Device

This answers:
- which exact FPGA chip are we compiling for?

For us:
- `5CSEMA5F31C6`

### 3. Pin assignments

This answers:
- which FPGA pins connect to clock, LEDs, switches, and GPIO header signals?

### 4. Timing constraint

This answers:
- what clock rate must the design meet?

For us:
- `CLOCK_50` at `50 MHz`

### 5. Programming file

This answers:
- what file actually goes onto the FPGA?

For us:
- `build/quartus/de1_soc_w5500.sof`

## The most important mental model

Use this simple model:

- `.v` files describe the hardware logic
- `.qsf` tells Quartus what the project is and how it connects to the board
- `.sdc` tells Quartus how fast the clocks are supposed to run
- compile turns all of that into a board-ready implementation
- `.sof` is the file that gets loaded into the FPGA

If you remember only one thing, remember that.

## Commands used in this repo

Recreate the Quartus project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

Run analysis and synthesis from the terminal:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_map.exe' --read_settings_files=on --write_settings_files=off de1_soc_w5500 -c de1_soc_w5500
```

Run full compile from the terminal:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500
```

Run one testbench in Questa console mode:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa.ps1 parser_tb
```

Open one testbench in Questa GUI:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa_gui.ps1 parser_tb
```

Open one testbench in Questa GUI and run it immediately:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_questa_gui.ps1 parser_tb -RunAll
```

## What to do next

Once you are comfortable with this guide, the next learning step is:
1. open the project in Quartus
2. look at the Files tab
3. open the Pin Planner
4. open the Compilation Report
5. open the Programmer
6. locate the generated `.sof`
7. program the board once

That sequence makes the Quartus concepts feel much more concrete.
