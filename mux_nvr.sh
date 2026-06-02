#!/bin/bash
# mux_nvr.sh — Concatenate renamed Hikvision NVR .mp4 files in groups of N
# Expects files already renamed by rename_nvr.sh (YYYY-MM-DD_HH-MM-SS_*.mp4)
# Output filename: YYYY-MM-DD_HH-MM-SS_mux.mp4 (timestamp of first file in group)

# ─── Help ────────────────────────────────────────────────────────────────────

usage() {
cat <<HELPEOF
Usage:
  $(basename "$0") [-n GROUP_SIZE] [-o OUTPUT_DIR] [-x]

Concatenates renamed Hikvision NVR .mp4 files (sorted by name) into groups,
remuxing audio and video with ffmpeg (no re-encoding, fast).

Running with no parameters shows this help and performs a dry run.

Options:
  -n GROUP_SIZE   Number of files per output file (default: 7)
  -o OUTPUT_DIR   Directory for output files (default: ./muxed)
  -x              Execute — actually create files (default is dry run)
  -h              Show this help message

Expected input filenames (as produced by rename_nvr.sh):
  2026-01-01_06-47-11_00000001264000000.mp4
  2026-01-01_07-11-47_00000001300000000.mp4
  ...

Output filenames use the timestamp of the first file in each group:
  2026-01-01_06-47-11_mux.mp4
  2026-01-01_09-39-29_mux.mp4
  ...
  The last group will contain the remaining files (fewer than GROUP_SIZE).

Example (dry run — safe, just prints what would happen):
  $(basename "$0") -n 7

Example (groups of 5, output to /tmp/out, live run):
  $(basename "$0") -n 5 -o /tmp/out -x

Notes:
  - Requires ffmpeg to be installed
  - Uses stream copy (no re-encoding) — fast and lossless
  - Input files must already be renamed with YYYY-MM-DD_HH-MM-SS_ prefix
HELPEOF
}

# ─── Defaults ────────────────────────────────────────────────────────────────

GROUP_SIZE=7
OUTPUT_DIR="./muxed"
DRY_RUN=true
NO_ARGS=true

# ─── Argument parsing ────────────────────────────────────────────────────────

while getopts ":n:o:xh" opt; do
    NO_ARGS=false
    case $opt in
        n) GROUP_SIZE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        x) DRY_RUN=false ;;
        h) usage; exit 0 ;;
        :) echo "Error: option -$OPTARG requires an argument." >&2; exit 1 ;;
        \?) echo "Error: unknown option -$OPTARG" >&2; usage; exit 1 ;;
    esac
done

# Show help + dry run when called with no arguments
if $NO_ARGS; then
    usage
    echo ""
    echo "════════════════════════════════════════"
    echo "No arguments given — running dry run with defaults (group size: $GROUP_SIZE)"
    echo "════════════════════════════════════════"
    echo ""
fi

# Force GROUP_SIZE to integer
GROUP_SIZE=$(( GROUP_SIZE + 0 ))
if [[ $GROUP_SIZE -lt 1 ]]; then
    echo "Error: GROUP_SIZE must be at least 1." >&2
    exit 1
fi

# ─── Validation ──────────────────────────────────────────────────────────────

if ! command -v ffmpeg &>/dev/null; then
    echo "Error: ffmpeg not found. Please install ffmpeg first." >&2
    exit 1
fi

# Collect and sort input files
mapfile -t FILES < <(ls [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_[0-9][0-9]-[0-9][0-9]-[0-9][0-9]_*.mp4 2>/dev/null | sort)

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "Error: no renamed .mp4 files found in current directory." >&2
    echo "Expected filenames like: 2026-01-01_06-47-11_originalname.mp4" >&2
    echo "Run rename_nvr.sh first." >&2
    exit 1
fi

TOTAL=${#FILES[@]}
GROUPS=$(( (TOTAL + GROUP_SIZE - 1) / GROUP_SIZE ))

echo "Found $TOTAL files → $GROUPS output file(s) of up to $GROUP_SIZE each"
echo "Output directory: $OUTPUT_DIR"
echo ""

if $DRY_RUN; then
    echo "*** DRY RUN — no files will be created. Use -x to execute. ***"
    echo ""
fi

# ─── Create output dir ───────────────────────────────────────────────────────

if ! $DRY_RUN; then
    mkdir -p "$OUTPUT_DIR"
fi

# ─── Process groups ──────────────────────────────────────────────────────────

TMPLIST=$(mktemp /tmp/mux_nvr_XXXXXX.txt)
trap 'rm -f "$TMPLIST"' EXIT

SUCCESS=0
ERRORS=0
GROUP_NUM=0

for (( i=0; i<TOTAL; i+=GROUP_SIZE )); do
    GROUP_NUM=$(( GROUP_NUM + 1 ))

    # Slice the group
    group=("${FILES[@]:$i:$GROUP_SIZE}")
    count=${#group[@]}

    # Output filename: timestamp of first file + _mux.mp4
    first="${group[0]}"
    ts="${first:0:19}"          # e.g. 2026-01-01_06-47-11
    outfile="${OUTPUT_DIR}/${ts}_mux.mp4"

    echo "Group ${GROUP_NUM}/${GROUPS}: ${count} file(s) → ${outfile}"
    for f in "${group[@]}"; do
        echo "  + $f"
    done

    if $DRY_RUN; then
        echo ""
        continue
    fi

    # Build ffmpeg concat list
    > "$TMPLIST"
    for f in "${group[@]}"; do
        echo "file '$(realpath "$f")'" >> "$TMPLIST"
    done

    # Run ffmpeg — stream copy, no re-encoding
    if ffmpeg -y -f concat -safe 0 -i "$TMPLIST" -c copy "$outfile" \
        -loglevel warning -stats; then
        echo "  ✓ Created: $outfile"
        (( SUCCESS++ )) || true
    else
        echo "  ✗ FAILED: $outfile" >&2
        (( ERRORS++ )) || true
    fi
    echo ""
done

echo ""
if $DRY_RUN; then
    echo "Dry run complete: $GROUPS output file(s) would be created."
    echo "Run with -x to execute."
else
    echo "Done: $SUCCESS succeeded, $ERRORS failed."
fi
