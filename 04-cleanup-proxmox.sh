#!/bin/bash
# =============================================================
# Cleanup Proxmox host RTL-SDR leftovers
# Run as root on Proxmox (192.168.68.50)
# =============================================================
set -e

echo "=== Stopping host rtl_tcp ==="
systemctl stop rtl_tcp 2>/dev/null || true
systemctl disable rtl_tcp 2>/dev/null || true
pkill -x rtl_tcp 2>/dev/null || true
sleep 1

echo "=== Removing systemd / modprobe / udev leftovers ==="
rm -f /etc/systemd/system/rtl_tcp.service
rm -f /etc/modprobe.d/blacklist-rtlsdr.conf
rm -f /etc/udev/rules.d/99-rtlsdr-power.rules
systemctl daemon-reload
udevadm control --reload-rules 2>/dev/null || true

echo "=== Checking for leftover processes ==="
if pgrep -a rtl_tcp >/dev/null 2>&1 || pgrep -a rtlamr >/dev/null 2>&1; then
  echo "WARNING: rtl processes still running:"
  pgrep -a rtl_tcp || true
  pgrep -a rtlamr || true
else
  echo "No rtl_tcp/rtlamr processes on host."
fi

echo "=== USB dongle present on host? ==="
lsusb | grep -iE '0bda:2838|RTL|Nooelec' || echo "WARNING: RTL-SDR not found via lsusb"

echo ""
echo "=== Done ==="
echo "Next: run 03-usb-passthrough.sh to pass the dongle into LXC 101."
