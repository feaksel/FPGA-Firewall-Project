# Demo Guide

This project has several demo styles, but they all use the same hardware path:

```text
PC1 Ethernet -> W5500 A -> DE1-SoC FPGA -> W5500 B -> PC2 Ethernet
```

Start the PC2 receiver first, then start the FPGA, then start the PC1 sender.
For a reliable presentation, begin at the safe pacing settings and only speed up
after the basic path is clean.

## Board Mode

Use normal forwarding mode for the final demos:

```text
SW0=1, SW5=0, SW6=0, SW7=0, SW8=0, SW9=0
```

The examples use `en0` for PC1 and `Ethernet` for PC2. Replace these with the
real interface names on your machines.

On PC2, list capture interfaces with:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --list-ifaces
```

On PC1, most sender scripts can print the IP/static-ARP setup commands:

```bash
python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --print-setup
python3 scripts/file_sender.py --iface en0 --file demo.mp4 --print-setup
```

The normal PC1 assumptions are:
- PC1 IP: `192.168.1.10`
- W5500 A IP: `192.168.1.1`
- W5500 A MAC: `02:00:00:de:ad:0a`
- allowed file/data service: UDP `5001`
- blocked decoy service: UDP `5002`

## Receiver Dashboards

Run one receiver dashboard on PC2 depending on the demo style.

| Dashboard | Command | Browser URL | Best for |
| --- | --- | --- | --- |
| Rule dashboard | `py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --port 8091` | `http://127.0.0.1:8091` | quick allow/drop proof, optional UART histogram |
| File/media dashboard | `py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092` | `http://127.0.0.1:8092` | files, images, video files, photo streams, webcam snapshots |
| Waveform dashboard | `py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090` | `http://127.0.0.1:8090` | live payload sample visualization |

Optional UART telemetry for the rule dashboard:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --uart COM7 --port 8091
```

Use a 3.3 V TTL USB-UART adapter wired from `GPIO_0_D6` to adapter RX, plus
ground. Do not connect the adapter 5 V pin.

The dashboard reset button resets the PC-side packet counters and also
baselines the FPGA UART counters from the latest raw telemetry line. The FPGA
hardware counters themselves only return to zero after `KEY0`, a reflash, or a
power cycle. The raw UART line is still shown under the histogram for evidence.

The file/media dashboard is also the webcam receiver. Webcam frames are sent as
normal JPEG file transfers with new `file_id` values, so no separate webcam
receiver is needed.

## Demo Style Summary

| Style | PC1 sender | PC2 receiver | What it proves |
| --- | --- | --- | --- |
| Simple rule demo | `rule_demo_udp_socket_sender.py` | rule dashboard | UDP/80 and UDP/5001 arrive; UDP/5002 and content blocks do not leak |
| Exact file transfer | `file_sender.py` | file dashboard | byte reconstruction and SHA-256 proof |
| Quick media demo | `media_demo_sender.py` | file dashboard | fast visual image/video preview through UDP/5001 |
| Photo folder stream | `photo_stream_sender.py` | file dashboard | repeated JPEG/PNG still-frame transfers |
| Webcam snapshot demo | `webcam_photo_sender.py` | file dashboard | live camera snapshots transferred through the FPGA path |
| Waveform demo | `sine_sender.py` | waveform dashboard | signed sample payloads forwarded as data, with visible gaps if packets are missed |

## Simple Rule Demo

Start PC2:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --port 8091
```

If the FPGA UART telemetry adapter is connected, start the same dashboard with
`--uart` and the COM port Windows assigned to the USB-UART adapter:

```powershell
py -3.9 .\scripts\rule_demo_receiver_dashboard.py --iface "Ethernet" --uart COM3 --baud 115200 --port 8091
```

Replace `COM3` with your actual port, for example `COM7`. The baud rate defaults
to `115200`, so `--baud 115200` is optional but useful when writing the command
down for a demo. If the dashboard says `pyserial is required for --uart`, install
it on PC2:

```powershell
py -3.9 -m pip install pyserial
```

Open:

```text
http://127.0.0.1:8091
```

Start PC1:

```bash
sudo python3 scripts/rule_demo_udp_socket_sender.py --iface en0 --rate 1 --verbose-each
```

This cycles through four profiles:

| Profile | Packet | Expected result |
| --- | --- | --- |
| allow80 | UDP/80 with `FW-DEMO-ALLOW80` | arrives on PC2 |
| allow5001 | UDP/5001 with `FWFILE1\0` marker | arrives on PC2 |
| drop5002 | UDP/5002 with `FW-UDP5002-DROP` marker | blocked |
| block80 | UDP/80 with `FW-BLOCK` marker | blocked by content override |

Expected dashboard result:
- allowed counts rise
- `Drop leaks` stays `0`
- FPGA UART histogram rises if UART is connected
- HEX receive/allow/drop pages move on the board

The FPGA rule counter meanings are:

| Field | Meaning | When it rises |
| --- | --- | --- |
| `U80` | UDP/80 allow rule | `allow80` sender profile |
| `U51` | UDP/5001 allow rule | file/media/sine/data profile |
| `D52` | UDP/5002 port-drop rule | UDP/5002 sender profile |
| `SIG` | content-block drop | payload contains `FW-BLOCK` or `FW-DEMO-DROP` |
| `DEF` | default drop | valid packet reaches the FPGA but matches none of the explicit rules |
| `FIL` | file marker seen | payload contains `FWFILE1\0` |
| `SIN` | sine marker seen | payload contains `FWSINE2\0` |

`DEF` is not expected to rise in the normal rule demo, because all default
profiles intentionally hit one of the explicit rules. It is useful when testing
unknown UDP ports or malformed/unsupported traffic. `SIN` only rises during the
waveform demo.

Use this demo first when the bench setup feels uncertain.

## Exact File Transfer Demo

Start PC2:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092
```

Open:

```text
http://127.0.0.1:8092
```

First prove the allow path with only a few chunks:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 0 --limit-chunks 4 --interval 0.10
```

Then run the policy proof:

```bash
sudo python3 scripts/file_sender.py --iface en0 --file demo.mp4 --decoys 1 --interval 0.10
```

What the file receiver shows:
- chunk progress
- missing chunks
- leak warnings for blocked packets
- reconstructed size
- expected SHA-256
- actual SHA-256
- browser preview after completion when the media type is supported

The default chunk size is `256` bytes and the safe interval is `0.10 s`. Keep
those defaults for the reliable proof. Smaller intervals are stress tests.

Because this is raw UDP, one missing allowed chunk correctly prevents SHA-256
PASS.

## Quick Media Demo

Use this when you want something visual quickly. The checked-in folder
`demo files/` contains:

| Profile | File |
| --- | --- |
| `jpg` | `demo_jpg.jpg` |
| `png` | `demo_png.png` |
| `gif` | `demo_gif.gif` |
| `mp4` | `demo_mp4.mp4` |
| `images` | JPG, PNG, GIF in sequence |
| `all` | JPG, PNG, GIF, MP4 in sequence |

Start PC2 with the file dashboard:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092
```

Fast visual image:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0
```

Try all image types:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile images --interval 0.10 --decoys 0
```

Policy proof with a visual file:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 1
```

Exact-original proof:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile png --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile gif --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile mp4 --decoys 1 --interval 0.10
```

The image profiles resize to a smaller JPEG by default when Pillow is installed,
because that makes the visual demo finish faster. Install Pillow on PC1 with:

```bash
python3 -m pip install pillow
```

Use `--original` when the point is byte-exact transfer instead of speed.

If chunks are missing, use repeated passes with the same `file_id`:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0 --retry-passes 3
```

For a smaller image payload:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --image-max-side 160 --image-target-kb 24 --interval 0.10 --decoys 0
```

## Photo Folder Stream

This is a still-frame stream. It sends complete JPEG/PNG files one after another
through the same UDP/5001 file path. It is not a compressed video codec.

Start PC2 with the file dashboard:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092
```

Loop through the checked-in media folder:

```bash
sudo python3 scripts/photo_stream_sender.py --iface en0 --dir "demo files" --loop --interval 0.10
```

Watch a folder and send new images as they appear:

```bash
sudo python3 scripts/photo_stream_sender.py --iface en0 --dir "demo files" --watch --interval 0.10
```

Useful options:
- `--patterns "*.jpg,*.jpeg,*.png"` selects file types.
- `--frame-gap 0.5` controls the gap after each completed image.
- `--file-id-start 100` controls the first transfer ID.
- `--decoys 1` adds blocked decoys for policy proof.

The receiver keeps the last completed image visible while the next `file_id` is
arriving.

## Webcam Snapshot Demo

The webcam demo captures JPEG snapshots on PC1 and sends each snapshot as a
normal `FWFILE1\0` UDP/5001 file transfer. PC2 uses the same file dashboard as
the file and media demos.

Install OpenCV on PC1:

```bash
python3 -m pip install opencv-python
```

Start PC2:

```powershell
py -3.9 .\scripts\file_receiver.py --iface "Ethernet" --port 8092
```

Open:

```text
http://127.0.0.1:8092
```

Send one webcam snapshot:

```bash
python3 scripts/webcam_photo_sender.py --iface en0 --count 1 --max-side 320 --interval 0.10
```

Send repeated snapshots until Ctrl+C:

```bash
python3 scripts/webcam_photo_sender.py --iface en0 --count 0 --period 2 --max-side 160 --jpeg-quality 65 --interval 0.10 --retry-passes 3 --file-id-start 600
```

What the options mean:
- `--count 1` sends one snapshot.
- `--count 0` runs continuously.
- `--period 2` captures a new snapshot every two seconds.
- `--max-side 160` resizes the JPEG so the transfer completes faster.
- `--jpeg-quality 65` balances image quality and payload size.
- `--retry-passes 3` sends the same snapshot three times with the same
  `file_id`, helping PC2 fill missed chunks.
- `--file-id-start 600` keeps webcam transfers separate from other demos.

If the camera does not open, try another camera index:

```bash
python3 scripts/webcam_photo_sender.py --iface en0 --camera-index 1 --count 1 --max-side 320 --interval 0.10
```

For a policy version of the webcam demo:

```bash
python3 scripts/webcam_photo_sender.py --iface en0 --count 0 --period 2 --max-side 160 --jpeg-quality 65 --interval 0.10 --retry-passes 3 --decoys 1
```

Expected result:
- PC2 previews each completed webcam JPEG.
- The preview stays on the last completed frame while the next one arrives.
- UDP/5002 and content-block decoys do not leak when `--decoys 1` is used.

### Fast Webcam Stress Mode

This mode is for showing that tiny snapshots can move quickly. It is not the
reliable proof mode.

```bash
python3 scripts/webcam_photo_sender.py --iface en0 --count 0 --period 0.0167 --max-side 160 --jpeg-quality 80 --interval 0.00111 --retry-passes 1 --file-id-start 1200
```

Meaning:
- `--period 0.0167` tries to capture about 60 snapshots per second.
- `--interval 0.00111` sends about 900 UDP datagrams per second.
- small JPEGs are required for this to be even somewhat practical.

Rule of thumb:

```text
packet_interval ~= snapshot_period / chunks_per_snapshot
```

Use this only after the safe `0.10 s` interval webcam demo works.

## Waveform Demo

This demo sends signed int16 sample values inside UDP/5001 payloads. The PC2
dashboard plots the received values. It does not synthesize the waveform locally.

Start PC2:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090
```

Open:

```text
http://127.0.0.1:8090
```

Start PC1:

```bash
sudo python3 scripts/sine_sender.py --iface en0 --wave sine --wave-hz 1 --packets-per-second 5
```

Other styles:

```bash
sudo python3 scripts/sine_sender.py --iface en0 --wave square --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave triangle --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave saw --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave step --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave noise --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave values --values "-28000 -28000 28000 28000 0 12000 24000 12000" --packets-per-second 5
sudo python3 scripts/sine_sender.py --iface en0 --wave text --text "FPGA UDP" --sample-rate 210 --samples-per-packet 21 --packets-per-second 10
```

Useful receiver lock for a clean presentation:

```powershell
py -3.9 .\scripts\sine_receiver_dashboard.py --iface "Ethernet" --port 8090 --lock-run-id 0x4321
```

Matching sender:

```bash
sudo python3 scripts/sine_sender.py --iface en0 --run-id 0x4321 --wave sine --wave-hz 1 --packets-per-second 5 --samples-per-packet 16
```

The sender can interleave blocked decoys with `--decoy-every` and
`--decoy-mode udp`, `content`, or `mixed`.

## Wireshark Checks

Allowed file/data traffic:

```text
udp.port == 5001
```

Blocked traffic that should not appear on PC2:

```text
udp.port == 5002
```

```text
frame contains "FW-BLOCK" || frame contains "FW-DEMO-DROP"
```

## Choosing a Demo

Use this order for a presentation:

1. Simple rule demo: fastest proof that forwarding and blocking work.
2. Quick media demo: visual proof with a small image.
3. Webcam snapshot demo: more impressive because PC1 captures live images.
4. Waveform demo: shows the payload is real data and gaps are visible.
5. Exact file transfer: strongest proof because SHA-256 must match.

Keep `--interval 0.10` for the reliable demos. Faster settings are useful only
after the safe path is already proven.
