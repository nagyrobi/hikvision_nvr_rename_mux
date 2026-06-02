# Hikvision NVR — Rename & Mux Scripts

Two bash scripts for working with `.mp4` files exported from a **Hikvision NVR** via its web interface.

The NVR gives files names like `00000001242000000.mp4` — numeric identifiers that do not sort into correct chronological order and carry no human-readable timestamp. These scripts solve both problems.

---

## Requirements

- Linux (bash)
- `ffmpeg` / `ffprobe` installed (`sudo apt install ffmpeg`)

---

## Scripts

### `rename_nvr.sh` — Determine real timestamps and rename files

Hikvision NVR export filenames are internal identifiers, not timestamps. The files also contain no embedded `creation_time` metadata. This script uses the internal `pts_time` (presentation timestamp) of each file, anchored to one known real-world time you supply manually, to compute the actual wall-clock start time of every file and rename them with a human-readable prefix.

**Output filename format:**
```
2026-01-01_08-01-08_00000001242000000.mp4
```

#### Usage

```bash
./rename_nvr.sh -a ANCHOR_FILE -t "YYYY-MM-DD HH:MM:SS" [-x]
```

| Option | Description |
|--------|-------------|
| `-a ANCHOR_FILE` | One `.mp4` file whose real start time you know (check by playing it) |
| `-t "YYYY-MM-DD HH:MM:SS"` | The known real start time of that file, in local time |
| `-x` | Execute — actually rename the files. Omit for a dry run (default) |
| `-h` | Show help |

#### Examples

```bash
# Dry run — safe, just prints what would happen
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-01-01 08:01:08"

# Live run — renames all .mp4 files in the current directory
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-01-01 08:01:08" -x
```

#### How it works

1. Reads the `pts_time` of the anchor file using `ffprobe`
2. Computes the offset between that `pts_time` and your supplied wall-clock time
3. Applies the same offset to every `.mp4` in the current directory
4. Renames each file with a `YYYY-MM-DD_HH-MM-SS_` prefix

The offset is consistent across all files in a recording session, so one anchor point is enough for the entire batch.

> **Note:** Run with a new anchor if you switch to a different recording session or camera. The pts offset is session-specific.

---

### `mux_nvr.sh` — Concatenate files in chronological order

After renaming, this script groups the files into larger combined recordings using `ffmpeg` stream copy (no re-encoding — fast and lossless). Files are sorted alphabetically by their new names, which puts them in correct chronological order.

**Output filename format** (timestamp of the first file in each group):
```
2026-01-01_06-47-11_mux.mp4
```

Output files are written to a `./muxed/` subdirectory by default, leaving the originals untouched.

#### Usage

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

#### Examples

```bash
# Dry run with defaults (7 files per group)
./mux_nvr.sh

# Live run — groups of 7, output to ./muxed
./mux_nvr.sh -x

# Groups of 5, custom output directory, live run
./mux_nvr.sh -n 5 -o /media/backup/video -x
```

#### How it works

1. Collects all files matching `YYYY-MM-DD_HH-MM-SS_*.mp4` in the current directory
2. Sorts them alphabetically (= chronologically after renaming)
3. Groups them in batches of `GROUP_SIZE`; the last group contains the remaining files
4. Concatenates each group with `ffmpeg -c copy` (stream copy, no quality loss)

> **Note:** Requires files to have been renamed by `rename_nvr.sh` first. The timestamp-prefixed filenames are what ensures correct sort order.

---

## Typical workflow

```bash
# Step 1 — figure out the real time of one file by playing it, then rename all
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-01-01 08:01:08"   # dry run
./rename_nvr.sh -a 00000001242000000.mp4 -t "2026-01-01 08:01:08" -x # apply

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

The scripts exploit the consistent `pts_time` offset to recover real wall-clock times without needing to decode or re-encode any video data.
