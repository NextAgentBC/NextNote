#!/usr/bin/env bash
# Batch-repair downloaded videos whose video track is VP9 or AV1 — AVPlayer
# (QuickTime / AVKit) silently drops the picture for those codecs on older /
# Intel Macs, so nextNote's in-app player shows audio only.
#
# Walks the given folder, probes each .mp4/.mkv/.webm with ffmpeg, and
# re-encodes only the ones that need it to HEVC (hvc1) via VideoToolbox
# hardware encode. Audio is copied, container stays mp4.
#
# Usage: scripts/repair-videos.sh <folder> [--dry-run]

set -euo pipefail

FOLDER="${1:-}"
DRY_RUN=0
if [[ "${2:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

if [[ -z "$FOLDER" || ! -d "$FOLDER" ]]; then
    echo "Usage: $0 <folder> [--dry-run]" >&2
    exit 1
fi

FFMPEG="${FFMPEG:-$(command -v ffmpeg || true)}"
if [[ -z "$FFMPEG" ]]; then
    for p in /opt/homebrew/bin/ffmpeg /usr/local/bin/ffmpeg; do
        [[ -x "$p" ]] && FFMPEG="$p" && break
    done
fi
if [[ -z "$FFMPEG" || ! -x "$FFMPEG" ]]; then
    echo "ffmpeg not found. brew install ffmpeg." >&2
    exit 1
fi

probe_codec() {
    # ffmpeg -i exits 1 (no output) but prints stream info to stderr.
    "$FFMPEG" -hide_banner -i "$1" 2>&1 \
        | awk -F'Video: ' '/Video: /{split($2,a,"[ ,]"); print tolower(a[1]); exit}'
}

needs_repair() {
    case "$1" in
        h264|hevc|h265) return 1 ;;
        "") return 1 ;;  # couldn't probe — leave alone
        *) return 0 ;;
    esac
}

transcode() {
    local src="$1"
    local tmp="${src%.*}.transcoding.mp4"
    rm -f "$tmp"
    "$FFMPEG" -y -hide_banner -nostats -nostdin \
        -i "$src" \
        -c:v hevc_videotoolbox -tag:v hvc1 -q:v 65 \
        -c:a copy \
        -movflags +faststart \
        "$tmp"
    mv -f "$tmp" "$src"
}

total=0
repaired=0
skipped=0
failed=0

while IFS= read -r -d '' f; do
    total=$((total + 1))
    codec=$(probe_codec "$f" || true)
    if needs_repair "$codec"; then
        printf '  REPAIR  %s  [%s]\n' "$f" "$codec"
        if [[ $DRY_RUN -eq 0 ]]; then
            if transcode "$f"; then
                repaired=$((repaired + 1))
            else
                failed=$((failed + 1))
                echo "    FAILED" >&2
            fi
        else
            repaired=$((repaired + 1))
        fi
    else
        skipped=$((skipped + 1))
        printf '  ok      %s  [%s]\n' "$f" "${codec:-unknown}"
    fi
done < <(find "$FOLDER" -type f \( -iname '*.mp4' -o -iname '*.mkv' -o -iname '*.webm' \) -print0)

echo
echo "Scanned : $total"
echo "Repaired: $repaired $([[ $DRY_RUN -eq 1 ]] && echo '(dry-run)')"
echo "Skipped : $skipped"
echo "Failed  : $failed"
