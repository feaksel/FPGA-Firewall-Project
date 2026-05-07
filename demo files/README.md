# Demo Media Folder

This folder contains presentation media for the FPGA UDP/5001 file-transfer
demo.

## Files

| File | Demo Use |
| --- | --- |
| `demo_jpg.jpg` | Still-image transfer and browser preview. Good for quick visual proof when resized by `media_demo_sender.py`. |
| `demo_png.png` | PNG transfer and browser preview. Larger than JPEG, useful to show the receiver is not hard-coded to one format. |
| `demo_gif.gif` | GIF transfer and browser preview. Optional visual media case. |
| `demo_mp4.mp4` | Video-file transfer and browser playback after the full file reconstructs and SHA-256 matches. |

The checked-in image/video files are around 1-2 MB. At the safest hardware
interval (`0.10 s` between datagrams, 256-byte chunks), byte-exact originals can
take several minutes. For a faster visual demo, use the media wrapper's default
image resizing. For checksum proof of the exact original, use `--original` or
`file_sender.py`.

Image resizing in `media_demo_sender.py` uses Pillow when available:

```bash
python3 -m pip install pillow
```

If Pillow is not installed, the wrapper falls back to sending original image
bytes, which is correct but slower.

## PC2 Receiver

Start this first on the PC connected to W5500 B:

```powershell
py -3 scripts\file_receiver.py --iface Ethernet --port 8092
```

Open:

```text
http://127.0.0.1:8092
```

The receiver auto-detects completed MP4/JPEG/PNG/GIF/MP3 payloads from bytes. If
the output path is the default `.bin`, it saves as `.mp4`, `.jpg`, `.png`,
`.gif`, or `.mp3` after the file completes.

## PC1 Quick Visual Image Demo

Use this first for a fast, visual presentation:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --interval 0.10 --decoys 0
```

What it does:
- reads `demo_jpg.jpg`,
- resizes it to a small JPEG payload by default,
- chunks it into `FWFILE1` UDP/5001 packets,
- sends it through W5500 A and the FPGA,
- lets PC2 reconstruct and preview it in the browser.

Try the other image formats:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile png --interval 0.10 --decoys 0
sudo python3 scripts/media_demo_sender.py --iface en0 --profile gif --interval 0.10 --decoys 0
sudo python3 scripts/media_demo_sender.py --iface en0 --profile images --interval 0.10 --decoys 0
```

`images` sends JPG, PNG, and GIF in sequence. The receiver automatically moves
to each new `file_id` and refreshes the preview. If the sender loops the exact
same image again, the receiver compares the SHA-256 and ignores the repeated
file instead of restarting the same preview.

Important: the fast visual image profiles resize JPG/PNG/GIF into a smaller
JPEG payload when Pillow is installed. That is intentional for speed. If you
want GIF-in/GIF-out, PNG-in/PNG-out, or exact original bytes, use `--original`.

## Exact Original File Proof

Use this when you want a byte-exact transfer and SHA-256 proof:

```bash
sudo python3 scripts/media_demo_sender.py --iface en0 --profile jpg --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile png --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile gif --original --decoys 1 --interval 0.10
sudo python3 scripts/media_demo_sender.py --iface en0 --profile mp4 --decoys 1 --interval 0.10
```

What this proves:
- allowed media chunks on UDP/5001 arrive at PC2,
- decoys on UDP/5002 or with `FW-BLOCK` do not leak,
- PC2 reconstructs the exact file and verifies SHA-256,
- browser preview works after completion when supported.

## Photo-By-Photo Stream

For a still-frame stream from this folder:

```bash
sudo python3 scripts/photo_stream_sender.py --iface en0 --dir "demo files" --loop --interval 0.10
```

This sends the JPEG/PNG files as successive complete image transfers. It is not
a video codec; it is a sequence of still images over the same FPGA UDP policy
path.

If another PC1 tool writes fresh images into a folder, use:

```bash
sudo python3 scripts/photo_stream_sender.py --iface en0 --dir "demo files" --watch --interval 0.10
```

`--watch` sends each new JPEG/PNG once as it appears.

## Webcam Snapshot Demo

Yes, PC1 can take webcam photos and send them to PC2 with the same FPGA path.
This needs OpenCV on PC1:

```bash
python3 -m pip install opencv-python
```

Then run:

```bash
sudo python3 scripts/webcam_photo_sender.py --iface en0 --count 1 --max-side 320 --interval 0.10
```

For repeated snapshots:

```bash
sudo python3 scripts/webcam_photo_sender.py --iface en0 --count 0 --period 2 --max-side 320 --interval 0.10
```

Each webcam snapshot becomes a JPEG file transfer with a new `file_id`, and PC2
previews the latest completed snapshot.

## Notes

- Use `--decoys 0` for the fastest visual media demo.
- Use `--decoys 1` when demonstrating policy enforcement.
- Use `--interval 0.10` for the stable proof. Smaller intervals are stress
  tests; missing chunks prevent SHA-256 pass and preview completion.
- Use small JPEG images for the smoothest live presentation.
