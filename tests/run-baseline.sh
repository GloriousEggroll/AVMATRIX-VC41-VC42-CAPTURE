#!/usr/bin/env bash
# Measure the loaded driver: frame delivery, V4L2 compliance, status thread
# state, IOMMU faults. Attach the output to an issue when reporting results.
#
# Needs: a 1920x1080 source connected to the channel under test and sending
# video, and no other app using the card (close OBS). Changing formats here is safe only because nothing else
# is streaming; an unfixed driver can crash if another app streams meanwhile.
#
# Usage: tests/run-baseline.sh [/dev/videoN]   (one node per input channel)
set -euo pipefail
DEV=${1:-/dev/video0}
HERE=$(cd "$(dirname "$0")" && pwd)
LOG=$(mktemp)
trap 'rm -f "$LOG"' EXIT

if fuser "$DEV" >/dev/null 2>&1; then
    echo "$DEV is in use (close OBS first):"; fuser -v "$DEV"; exit 1
fi

# Store the live input's DV timings first. Otherwise v4l2-ctl sees "new timings"
# at stream start and sets them, which (per V4L2) resets the format to the input
# size and overrides the --set-fmt-video below.
v4l2-ctl -d "$DEV" --set-dv-bt-timings query >/dev/null 2>&1 || true

echo "## $(date -Iseconds)"
echo "module srcversion: $(cat /sys/module/HwsCapture/srcversion 2>/dev/null || echo not-loaded)"
echo "repo HEAD: $(git -C "$HERE/.." rev-parse --short HEAD)"
echo "kernel: $(uname -r)"
echo

# name width height buffers count
runs=(
  "1080p-native-4buf 1920 1080 4 300"
  "1080p-native-1buf 1920 1080 1 300"
  "720p-scaled-4buf 1280 720 4 300"
)
for r in "${runs[@]}"; do
    read -r name w h nbuf count <<<"$r"
    echo "### $name ($w x $h, $nbuf MMAP buffers, $count frames)"
    # framecheck reads the log only after stdin closes, when v4l2-ctl has exited
    # shellcheck disable=SC2094
    v4l2-ctl -d "$DEV" --set-fmt-video=width="$w",height="$h",pixelformat=YUYV \
        --stream-mmap="$nbuf" --stream-count="$count" --stream-to=- --verbose 2>"$LOG" \
      | python3 -I "$HERE/framecheck.py" - "$LOG" $((w * h * 2))
    echo
done

echo "### v4l2-compliance (no streaming tests)"
# v4l2-compliance exits non-zero when tests fail; that is a result, not an error.
# Drivers without the per-queue locking fix deadlock in its blocking-DQBUF
# test, so cap the run.
{ timeout -s KILL 120 v4l2-compliance -d "$DEV" 2>&1 || echo "v4l2-compliance: exit $? (137 = killed after 120 s, likely the blocking-DQBUF deadlock)"; } \
    | grep -E 'Total|fail:|exit [0-9]' | sed 's/^[[:space:]]*//' || true
echo

echo "### status thread and load"
ps -eo pid,stat,comm | awk '/StartKSThread/ {print "StartKSThread state: " $2}'
echo "loadavg: $(cut -d' ' -f1-3 /proc/loadavg)"
echo

echo "### IOMMU faults this boot"
journalctl -k -b --no-pager 2>/dev/null | grep -c 'HwsCapture.*IO_PAGE_FAULT' || true
