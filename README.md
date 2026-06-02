# Hikvision NVR — Rename & Mux Scripts

Two bash scripts for working with `.mp4` files exported from a **Hikvision NVR** via its web interface (usually via the "Download by File" functionality, saving the files one by one).

The NVR gives files names like `00000001242000000.mp4` — numeric identifiers that do not sort into correct chronological order and carry no human-readable timestamp. The files experience playback issues with certain third party players, remuxing them is recommended for smooth playback.

---

## Requirements

- Linux (bash)
- `ffmpeg` / `ffprobe` installed (`sudo apt install ffmpeg`)

---

## `rename_nvr.sh` — Determine real timestamps and rename files

Hikvision NVR export filenames are internal identifiers, not timestamps. The files also contain no embedded creation time metadata. This script uses the internal presentation timestamp of each MP4 file, anchored to one known real-world time you supply manually, to compute the actual wall-clock start time of every file and rename them with a human-readable prefix. Output filename format: `2026-01-01_08-01-08_00000001242000000.mp4`

### Usage

```bash
./rename_nvr.sh -a ANCHOR_FILE -t "YYYY-MM-DD HH:MM:SS" [-x]
```

| Option | Description |
|--------|-------------|
| `-a ANCHOR_FILE` | One `.mp4` file whose real start time you know (check by playing it) |
| `-t "YYYY-MM-DD HH:MM:SS"` | The known real start time of that file, in local time |
| `-x` | Execute — actually rename the files. Omit for a dry run (default) |
| `-h` | Show help |

### Examples

```bash
# Dry run — safe, just prints what would happen
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-06-01 08:01:07"
Reading pts_time from anchor file: 00000001242000000.mp4
Anchor pts_time : 11633.571311
Anchor wall time: 2026-06-01 08:01:07 (epoch: 1780293667)
Computed offset : 1780282033 seconds

*** DRY RUN — no files will be renamed. Use -x to execute. ***

  00000001242000000.mp4  →  2026-06-01_08-01-07_00000001242000000.mp4
  00000001264000000.mp4  →  2026-06-01_06-47-11_00000001264000000.mp4
  ...
  00000001429000000.mp4  →  2026-06-01_16-32-31_00000001429000000.mp4
  00000001486000000.mp4  →  2026-06-01_17-46-03_00000001486000000.mp4

Dry run complete: 28 files would be renamed, 0 skipped.
Run with -x to apply.
```

```bash
# Live run — renames all .mp4 files in the current directory
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-06-01 08:01:07" -x
```

### How it works

1. Reads the `pts_time` of the anchor file using `ffprobe`
2. Computes the offset between that `pts_time` and your supplied wall-clock time
3. Applies the same offset to every `.mp4` in the current directory
4. Renames each file with a `YYYY-MM-DD_HH-MM-SS_` prefix

The offset is consistent across all files in a recording session, so one anchor point is enough for the entire batch.

> **Note:** Run with a new anchor if you switch to a different recording session or camera. The pts offset is session-specific.

---

## `mux_nvr.sh` — Concatenate files in chronological order

After renaming with `rename_nvr.sh`, this script groups the files into larger combined recordings using `ffmpeg` stream copy (no re-encoding — fast and lossless). This also fixes playback issues on some systems. Files are sorted alphabetically by their new names, which puts them in correct chronological order. 

By default the script muxes 7 files in one, as usually a file duration is around 25 minutes, thus obtaining remuxed files of roughly 3 hours long.

Output filename format (timestamp of the first file in each group): `2026-01-01_06-47-11_mux.mp4`, they are written to a `./muxed/` subdirectory by default, leaving the originals untouched.

### Usage

```bash
./mux_nvr.sh [-n GROUP_SIZE] [-o OUTPUT_DIR] [-x]
```

| Option | Description |
|--------|-------------|
| `-n GROUP_SIZE` | Number of input files per output file (default: `7`) |
| `-o OUTPUT_DIR` | Directory for output files (default: `./muxed`) |
| `-x` | Execute — actually create files. Omit for a dry run (default) |
| `-h` | Show help |

Running with **no arguments** prints help and performs a dry run with default settings.

### Examples

```bash
# Dry run with defaults (7 files per group)
./mux_nvr.sh
```

```bash
# Live run — groups of 7, output to ./muxed
./mux_nvr.sh -x
Found 28 files → 1000 output file(s) of up to 7 each
Output directory: ./muxed

Group 1/1000: 7 file(s) → ./muxed/2026-06-01_06-47-11_mux.mp4
  + 2026-06-01_06-47-11_00000001264000000.mp4
  ...
  + 2026-06-01_09-15-07_00000001327000000.mp4
frame=258457 fps=10075 q=-1.0 Lsize= 7250496KiB time=03:00:24.11 bitrate=5487.4kbits/s speed= 422x    
  ✓ Created: ./muxed/2026-06-01_06-47-11_mux.mp4

...

Group 4/1000: 7 file(s) → ./muxed/2026-06-01_15-19-51_mux.mp4
  + 2026-06-01_15-19-51_00000001407000000.mp4
  ...
  + 2026-06-01_17-46-03_00000001486000000.mp4
frame=256107 fps=8911 q=-1.0 Lsize= 7249172KiB time=02:58:51.80 bitrate=5533.6kbits/s speed= 373x    
  ✓ Created: ./muxed/2026-06-01_15-19-51_mux.mp4
```

```bash
# Groups of 5, custom output directory, live run
./mux_nvr.sh -n 5 -o /media/backup/video -x
```

### How it works

1. Collects all files matching `YYYY-MM-DD_HH-MM-SS_*.mp4` in the current directory
2. Sorts them alphabetically (= chronologically after renaming)
3. Groups them in batches of `GROUP_SIZE`; the last group contains the remaining files
4. Concatenates each group with `ffmpeg -c copy` (stream copy, no quality loss)

> **Note:** Requires files to have been renamed by `rename_nvr.sh` first. The timestamp-prefixed filenames are what ensures correct sort order.

---

## Typical workflow

```bash
# Step 1 — figure out the real time of one file by playing it, then rename all
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-06-01 08:01:07"       # dry run
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-06-01 08:01:07" -x    # apply

# Step 2 — preview grouping
./mux_nvr.sh

# Step 3 — create combined files
./mux_nvr.sh -x
```

---

## Background

Hikvision NVR web export produces `.mp4` files with:
- Opaque numeric filenames that do not reflect recording time
- No `creation_time` or other timestamp metadata
- A shared internal `pts_time` timeline that is consistent within a session
- Files experience playback issues with certan third party players, remuxing them is needed for smooth playback

The scripts are based on the consistent `pts_time` offset to recover real wall-clock times without needing to decode or re-encode any video data.
