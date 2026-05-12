# ELE432 FPGA UDP Policy Gateway

This repository is my ELE432 FPGA networking project. The original idea was a
small FPGA firewall, but the version that is actually working on the bench is
more specific: a W5500-based UDP policy gateway.

The real demo path is:

```text
PC1 sender -> W5500 A -> FPGA policy logic -> W5500 B -> PC2 receiver
```

PC1 sends UDP packets into the first W5500 module. The FPGA reconstructs an
internal Ethernet/IPv4/UDP byte stream, checks the packet service and payload
markers, and forwards only the allowed packets through the second W5500 module.
PC2 then proves the result with Wireshark or the browser dashboards.

## Current State

The latest recorded hardware status in this repo is from 2026-05-07.

What is working:
- DE1-SoC programming through USB-Blaster/JTAG.
- W5500 SPI register access and initialization.
- W5500 A UDP socket receive on the hardware path.
- W5500 B transmit to PC2.
- UDP/80 and UDP/5001 forwarding through the FPGA policy path.
- UDP/5002 and content-marker drop logic in the RTL.
- Browser dashboards for rule, waveform, and file-transfer demos.
- Simulation testbenches for the parser, rules, buffers, W5500 models, and top-level paths.

What is still a project limitation:
- This is not a transparent L2/TCP firewall.
- The old MACRAW path is kept as debug history, not the final demo path.
- The file demo uses raw UDP, so it has no retransmission. If a chunk is missed,
  the receiver correctly refuses to mark the file as a SHA-256 pass.
- The remaining final proof is the full safe-rate file transfer with decoys,
  no leaks, and a matching SHA-256 on PC2.

## Documentation

The docs have been organized for MkDocs.

Once GitHub Pages is enabled for this repository, the public docs should be
available here:

```text
https://feaksel.github.io/FPGA-Firewall-Project/
```

The workflow in `.github/workflows/pages.yml` builds and publishes the docs
automatically after pushes to `main`.

If the workflow fails at `Configure GitHub Pages` with a `Not Found` error,
open the repository on GitHub and go to:

`Settings` -> `Pages` -> `Build and deployment` -> `Source` -> `GitHub Actions`

Direct setup page for this repository:

```text
https://github.com/feaksel/FPGA-Firewall-Project/settings/pages
```

Then rerun the failed workflow. This setting usually has to be selected once
for a new Pages site before the workflow can deploy successfully.

If the public homepage opens but looks like GitHub's plain Jekyll rendering of
this README instead of the MkDocs sidebar site, Pages is still set to
`Deploy from a branch`. Switch the same setting to `GitHub Actions`; otherwise
GitHub will serve the repository files directly instead of the MkDocs build.

To view them locally:

```powershell
py -3 -m pip install -r requirements-docs.txt
py -3 -m mkdocs serve
```

Then open:

```text
http://127.0.0.1:8000
```

Main pages:
- [Project documentation](docs/index.md)
- [Current status](docs/status.md)
- [Architecture](docs/architecture.md)
- [Hardware setup](docs/hardware.md)
- [Demo guide](docs/demo.md)
- [Simulation and tests](docs/verification.md)
- [Quartus build](docs/quartus.md)
- [Code map](docs/code-map.md)
- [Interfaces](docs/interfaces.md)
- [Debugging notes](docs/debugging.md)
- [Archived notes](docs/archive/README.md)

## Repository Map

- `rtl/` - synthesizable Verilog for the FPGA design.
- `tb/` - SystemVerilog/Verilog testbenches, W5500 models, and packet vectors.
- `scripts/` - simulation runners, traffic senders, dashboards, and capture tools.
- `quartus/` - Quartus project files and pin/constraint setup.
- `docs/` - the MkDocs documentation source.
- `docs/archive/` - older logs, plans, decisions, and long debug notes.
- `demo files/` - media used by the visual file-transfer demo.
- `captures/` - saved SignalTap and capture evidence from bench work.

## Common Commands

Run the main simulation suite:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim_suite.ps1
```

Run one testbench:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_xsim.ps1 parser_tb
```

Refresh the Quartus project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\create_quartus_project.ps1
```

Compile in Quartus:

```powershell
& 'C:\altera_lite\25.1std\quartus\bin64\quartus_sh.exe' --flow compile de1_soc_w5500 -c de1_soc_w5500
```

Start the PC2 file dashboard:

```powershell
py -3 scripts\file_receiver.py --iface Ethernet --port 8092
```

Send a quick media demo from PC1:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0
```

For the checked-in media files, see [demo files/README.md](demo%20files/README.md).
