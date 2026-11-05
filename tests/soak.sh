#!/usr/bin/env bash
# Log a long OBS capture session on one channel (root via sudo for debugfs).
#
# Usage: tests/soak.sh [HOURS] [INTERVAL_MIN]   (defaults 8 and 30)
#   CH=n  input channel (default 0)
#
# Start OBS capturing from the channel first. Every INTERVAL_MIN minutes,
# and at the end, prints one row: the channel's frame rate over the
# interval, frames lost, frames failed for a late copy, audio gaps the
# driver filled with silence, OBS's resident memory, available system
# memory, and the IO_PAGE_FAULT and PipeWire error counts since the start.
set -uo pipefail
CH=${CH:-0}
BDF=${BDF:-$(basename "$(ls -d /sys/bus/pci/drivers/HwsCapture/0000:* 2>/dev/null | head -1)")}
[ -n "$BDF" ] || { echo "no card bound to HwsCapture"; exit 1; }
DBG=/sys/kernel/debug/hws-$BDF
hours=${1:-8} every=${2:-30}
# this channel's block of the debugfs status file, without the indent
st() { sudo -n cat "$DBG/status" | awk -v ch="channel $CH" '/^channel /{on = ($0 == ch); next} on {sub(/^ +/, ""); print}'; }
num() { st | awk -v k="$1" -v n="$2" 'index($0,k)==1 {gsub(",",""); print $n}'; }
since=$(date '+%Y-%m-%d %H:%M:%S')
kcount() { journalctl -k --since "$since" --no-pager | grep -c "$1" || true; }
pwerr() { journalctl --user --since "$since" --no-pager -u pipewire -u wireplumber -u pipewire-pulse \
    | grep -ciE "error|xrun" || true; }
obs_rss() { local p; p=$(pgrep -n -x obs) && awk '/VmRSS/{printf "%d MiB", $2/1024}' "/proc/$p/status" || echo "not running"; }

pgrep -x obs >/dev/null || { echo "start OBS capturing first"; exit 1; }
echo "soak: card $BDF channel $CH, ${hours} h, a row every ${every} min, from $since; $(st | grep '^input')"
printf '| time | fps | lost | late copies | audio gaps | OBS RSS | MemAvailable | IO_PAGE_FAULT | PipeWire errors |\n'
printf '|---|---|---|---|---|---|---|---|---|\n'
row() {
    local f1 t1
    f1=$(num "frames:" 2) t1=$(date +%s.%N)
    printf '| %s | %s | %s | %s | %s | %s | %s MiB | %s | %s |\n' "$(date +%H:%M)" \
        "$(echo "scale=2; ($f1 - $f0) / ($t1 - $t0)" | bc)" "$(num "frames:" 4)" \
        "$(st | sed -nE 's/^frames:.*copy ended late: ([0-9]+).*/\1/p')" \
        "$(st | sed -nE 's/^audio: gaps filled with silence: ([0-9]+).*/\1/p')" \
        "$(obs_rss)" "$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)" \
        "$(kcount IO_PAGE_FAULT)" "$(pwerr)"
    f0=$f1 t0=$t1
}
f0=$(num "frames:" 2) t0=$(date +%s.%N)
sleep 60
row
end=$(( $(date +%s) + hours * 3600 ))
while [ "$(date +%s)" -lt "$end" ]; do
    sleep $(( every * 60 ))
    row
done
