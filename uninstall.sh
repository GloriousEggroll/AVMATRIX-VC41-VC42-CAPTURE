#!/usr/bin/env bash
# Remove the AVMatrix VC41/VC42 driver (HwsCapture): every version install.sh or the
# development tools added to DKMS, and everything the older installers
# (scripts/hws-*.sh) left behind.
set -euo pipefail
[ "$(id -u)" -eq 0 ] || exec sudo -- "$0" "$@"

MODULE=HwsCapture
shopt -s nullglob

# DKMS: this package, and the name the old DKMS installer used
for name in HwsCaptureForLinux HwsCapture.ko; do
    for d in /var/lib/dkms/"$name"/*/; do
        ver=$(basename "$d")
        case "$ver" in kernel-*|source) continue ;; esac
        echo "Removing $name $ver from DKMS"
        dkms remove -m "$name" -v "$ver" --all >/dev/null 2>&1 || true
    done
    rm -rf "/var/lib/dkms/$name"
done
for p in /usr/src/HwsCaptureForLinux-* /usr/src/HwsCapture.ko-* /usr/src/HwsCapture.ko_*; do
    echo "Removing $p"
    rm -rf "$p"
done

# the old installers' copy of the sources and their /usr/bin links
if [ -e /usr/local/share/HWS ]; then
    echo "Removing /usr/local/share/HWS"
    rm -rf /usr/local/share/HWS
fi
for l in /usr/bin/hws-*.sh; do
    echo "Removing $l"
    rm -f "$l"
done

# modules a non-DKMS install copied into the kernel trees
while IFS= read -r -d '' f; do
    echo "Removing $f"
    rm -f "$f"
done < <(find /lib/modules -name "$MODULE.ko*" -print0 2>/dev/null)

for k in /lib/modules/*/; do
    [ -e "$k/modules.order" ] || continue
    depmod -a "$(basename "$k")" 2>/dev/null || true
done

# install.sh's blacklist of the in-kernel hws driver
if [ -e /etc/modprobe.d/hws-capture.conf ]; then
    echo "Removing /etc/modprobe.d/hws-capture.conf (the in-kernel hws driver may load again)"
    rm -f /etc/modprobe.d/hws-capture.conf
fi
if [ -e /etc/modprobe.d/hws.conf ]; then
    echo "Left /etc/modprobe.d/hws.conf in place (your module options)."
fi
if [ -d "/sys/module/$MODULE" ]; then
    echo "The driver is still loaded. Reboot to unload it."
else
    echo "Done."
fi
