#!/bin/bash
# rename_nvr.sh — Hikvision NVR: rename .mp4 files with real wall-clock timestamp prefix
# Usage: rename_nvr.sh -a ANCHOR_FILE -t "YYYY-MM-DD HH:MM:SS" [-x]



# ─── Help ────────────────────────────────────────────────────────────────────

usage() {
cat <<EOF
Usage:
  $(basename "$0") -a ANCHOR_FILE -t "YYYY-MM-DD HH:MM:SS" [-x]

Renames Hikvision NVR .mp4 files in the current directory by prepending the
real wall-clock start time derived from an anchor file you identify manually.

Options:
  -a ANCHOR_FILE   One .mp4 file whose real start time you know
  -t TIMESTAMP     The known real start time of that file, in local time
                   Format: "YYYY-MM-DD HH:MM:SS"  e.g. "2026-01-01 08:01:08"
  -x               Execute — actually rename the files (default is dry run)
  -h               Show this help message

Example (dry run — safe, just prints what would happen):
  $(basename "$0") -a 00000001242000000.mp4 -t "2026-01-01 08:01:08"

Example (live run — renames files):
  $(basename "$0") -a 00000001242000000.mp4 -t "2026-01-01 08:01:08" -x

How it works:
  The script reads the internal pts_time of the anchor file, computes the
  offset to your supplied wall-clock time, then applies that offset to every
  .mp4 file in the current directory to produce a sorted, timestamped name:
    2026-01-01_08-01-08_00000001242000000.mp4

Notes:
  - Requires ffprobe (part of ffmpeg) to be installed
  - Times are interpreted as local time (no timezone conversion)
  - Re-run with a new anchor if you switch to a different recording session
EOF
}

# ─── Defaults ────────────────────────────────────────────────────────────────

ANCHOR_FILE=""
ANCHOR_TIME=""
DRY_RUN=true

# ─── Argument parsing ─────────────────────────────────────────────────────────

if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

while getopts ":a:t:xh" opt; do
    case $opt in
        a) ANCHOR_FILE="$OPTARG" ;;
        t) ANCHOR_TIME="$OPTARG" ;;
        x) DRY_RUN=false ;;
        h) usage; exit 0 ;;
        :) echo "Error: option -$OPTARG requires an argument." >&2; exit 1 ;;
        \?) echo "Error: unknown option -$OPTARG" >&2; usage; exit 1 ;;
    esac
done

# ─── Validation ──────────────────────────────────────────────────────────────

if [[ -z "$ANCHOR_FILE" || -z "$ANCHOR_TIME" ]]; then
    echo "Error: both -a and -t are required." >&2
    echo "Run '$(basename "$0") -h' for usage." >&2
    exit 1
fi

if [[ ! -f "$ANCHOR_FILE" ]]; then
    echo "Error: anchor file not found: $ANCHOR_FILE" >&2
    exit 1
fi

if ! command -v ffprobe &>/dev/null; then
    echo "Error: ffprobe not found. Install ffmpeg first." >&2
    exit 1
fi

# ─── Compute offset ──────────────────────────────────────────────────────────

echo "Reading pts_time from anchor file: $ANCHOR_FILE"

ANCHOR_PTS=$(ffprobe -v quiet -select_streams v:0 \
    -show_entries packet=pts_time \
    -of csv=print_section=0 \
    "$ANCHOR_FILE" 2>/dev/null | head -1)

if [[ -z "$ANCHOR_PTS" ]]; then
    echo "Error: could not read pts_time from $ANCHOR_FILE" >&2
    exit 1
fi

# Convert anchor wall-clock time to seconds since epoch (using local time)
ANCHOR_EPOCH=$(date -d "$ANCHOR_TIME" +%s)

# pts_time may be a decimal — truncate to integer before subtracting
ANCHOR_PTS_INT=$(LC_NUMERIC=C printf "%.0f" "$ANCHOR_PTS")

# offset = wall_clock_epoch - pts_time
OFFSET=$(( ANCHOR_EPOCH - ANCHOR_PTS_INT ))

echo "Anchor pts_time : $ANCHOR_PTS"
echo "Anchor wall time: $ANCHOR_TIME (epoch: $ANCHOR_EPOCH)"
echo "Computed offset : $OFFSET seconds"
echo ""

if $DRY_RUN; then
    echo "*** DRY RUN — no files will be renamed. Use -x to execute. ***"
    echo ""
fi

# ─── Rename loop ─────────────────────────────────────────────────────────────

COUNT=0
ERRORS=0

for f in *.mp4; do
    pts=$(ffprobe -v quiet -select_streams v:0 \
        -show_entries packet=pts_time \
        -of csv=print_section=0 \
        "$f" 2>/dev/null | head -1)

    if [[ -z "$pts" ]]; then
        echo "WARN: skipping $f (could not read pts_time)" >&2
        ((ERRORS++)) || true
        continue
    fi

    pts_int=$(LC_NUMERIC=C printf "%.0f" "$pts")
    wall_epoch=$(( pts_int + OFFSET ))
    timestamp=$(date -d "@$wall_epoch" "+%Y-%m-%d_%H-%M-%S")
    newname="${timestamp}_${f}"

    if $DRY_RUN; then
        echo "  $f  →  $newname"
    else
        mv "$f" "$newname"
        echo "Renamed: $f  →  $newname"
    fi

    ((COUNT++)) || true
done

echo ""
if $DRY_RUN; then
    echo "Dry run complete: $COUNT files would be renamed, $ERRORS skipped."
    echo "Run with -x to apply."
else
    echo "Done: $COUNT files renamed, $ERRORS skipped."
fi
