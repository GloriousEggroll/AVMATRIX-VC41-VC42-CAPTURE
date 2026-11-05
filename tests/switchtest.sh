#!/usr/bin/env bash
# Capture at a fixed size on one channel while someone switches that
# channel's source between resolutions (OBS closed, root via sudo).
#
# Usage: tests/switchtest.sh WIDTH HEIGHT [CHANGES]
#   CH=n     input channel (default 0); DEV=/dev/videoN its video node
#   LOG=path keep the v4l2-ctl log
#
# Streams WIDTH x HEIGHT through framecheck.py and logs each input-size
# change the driver sees on that channel (the "no usable signal" between two
# sizes is not a change), with how long the frame counter then stalled.
# Stops after CHANGES changes (default 40: 20 each way) or on Ctrl-C, then
# prints the frame check, the channel's counters and kernel log lines that
# would show a problem.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CH=${CH:-0}
DEV=${DEV:-/dev/video0}
BDF=${BDF:-$(basename "$(ls -d /sys/bus/pci/drivers/HwsCapture/0000:* 2>/dev/null | head -1)")}
[ -n "$BDF" ] || { echo "no card bound to HwsCapture"; exit 1; }
DBG=/sys/kernel/debug/hws-$BDF
w=${1:?width} h=${2:?height} want=${3:-40}
OUT=$(mktemp -d)
trap '[ -n "${LOG:-}" ] && [ -e "$OUT/cap.log" ] && cp "$OUT/cap.log" "$LOG"; rm -rf "$OUT"' EXIT

# OBS may stay open to show the source (WITH_OBS=1).
[ -z "${WITH_OBS:-}" ] && pgrep -x obs >/dev/null && { echo "close OBS first, or set WITH_OBS=1"; exit 1; }
# this channel's block of the debugfs status file
st() { sudo -n cat "$DBG/status" | awk -v ch="channel $CH" '/^channel /{on = ($0 == ch); next} on'; }
st | grep -q "engine restarts" || { echo "the loaded driver has no restart counter, or channel $CH doesn't exist"; exit 1; }
count() { journalctl -k -b --no-pager | grep -c "$1" || true; }
pats=(IO_PAGE_FAULT "WARNING:" "BUG:" "lost its run state")
declare -A base
for p in "${pats[@]}"; do base[$p]=$(count "$p"); done
echo "card $BDF channel $CH ($DEV), capturing ${w}x${h}"
echo "before: $(st | grep 'engine restarts' | sed 's/^ *//')"

# Another app streaming (OBS) can keep the channel at its own size; check
# the size this stream really gets, since framecheck cuts frames by it.
v4l2-ctl -d "$DEV" --set-fmt-video=width="$w",height="$h",pixelformat=YUYV >/dev/null 2>&1
read -r gw gh < <(v4l2-ctl -d "$DEV" --get-fmt-video | awk -F'[ /:]+' '/Width\/Height/{print $3, $4}')
[ "$gw" = "$w" ] && [ "$gh" = "$h" ] || echo "note: the channel stays at ${gw}x${gh} (another app holds the format); capturing that"
w=$gw h=$gh
# framecheck reads the log only after stdin closes, when v4l2-ctl has exited
# shellcheck disable=SC2094
v4l2-ctl -d "$DEV" --set-fmt-video=width="$w",height="$h",pixelformat=YUYV \
    --stream-mmap=4 --stream-count=10000000 --stream-to=- --verbose 2>"$OUT/cap.log" \
  | python3 -I "$HERE/framecheck.py" - "$OUT/cap.log" $((w * h * 2)) >"$OUT/check" &
sleep 1
cap=$(pgrep -n -x v4l2-ctl)

frames() { st | awk '$1 == "frames:" {sub(",", "", $2); print $2}'; }
input() { st | awk '$1 == "input:" {print $2}'; }
stop=0
trap 'stop=1' INT
cur=$(input) n=0
until [[ $cur =~ ^[0-9]+x[0-9]+$ ]]; do sleep 0.05; cur=$(input); done
echo "input $cur; switch the source now ($want changes, Ctrl-C to stop early)"
while [ "$stop" = 0 ] && [ "$n" -lt "$want" ] && kill -0 "$cap" 2>/dev/null; do
    sleep 0.05
    now=$(input)
    # a switch passes through "no usable signal"; count only size to size
    [[ $now =~ ^[0-9]+x[0-9]+$ ]] || continue
    [ "$now" = "$cur" ] && continue
    t0=$(date +%s.%N) f0=$(frames)
    n=$((n + 1))
    # the frame counter also counts no-signal frames, so this is how long
    # the counter stalled, not the time to a picture
    while [ "$(frames)" = "$f0" ] && [ "$stop" = 0 ]; do sleep 0.01; done
    printf '%2d  %s -> %s  frame counter moved after %.0f ms\n' "$n" "$cur" "$now" \
        "$(echo "($(date +%s.%N) - $t0) * 1000" | bc)"
    cur=$now
done
trap - INT
kill -TERM "$cap" 2>/dev/null   # background jobs ignore SIGINT
wait
sed 's/^/  /' "$OUT/check"
echo "after: $(st | grep 'engine restarts' | sed 's/^ *//')"
st | grep -E "frames:" | sed 's/^ *//'
for p in "${pats[@]}"; do printf '%s +%d, ' "$p" $(( $(count "$p") - ${base[$p]} )); done
echo
