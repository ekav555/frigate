#!/bin/bash
# =============================================================
# Pass RTL-SDR USB into Frigate LXC 101
# Run as root on Proxmox (192.168.68.50)
# =============================================================
set -e

CT_ID=101
LXC_CONF="/etc/pve/lxc/${CT_ID}.conf"

if ! pct status $CT_ID &>/dev/null; then
  echo "ERROR: Container $CT_ID not found"
  exit 1
fi

echo "=== RTL-SDR on host ==="
lsusb | grep -iE '0bda:2838|RTL|Nooelec' || {
  echo "ERROR: RTL-SDR USB device not found. Plug it in and retry."
  exit 1
}

echo "=== Ensuring USB passthrough in $LXC_CONF ==="
if grep -q 'lxc.mount.entry: /dev/bus/usb' "$LXC_CONF"; then
  echo "USB mount entry already present."
else
  cat >> "$LXC_CONF" << 'EOF'

# RTL-SDR USB passthrough for rtlamr2mqtt
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
EOF
  echo "USB passthrough lines appended."
fi

# Also keep GPU lines if missing (Frigate)
if ! grep -q 'lxc.mount.entry: /dev/dri' "$LXC_CONF"; then
  cat >> "$LXC_CONF" << 'EOF'
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
  echo "GPU passthrough lines appended."
fi

echo "=== Rebooting LXC $CT_ID ==="
pct reboot $CT_ID
sleep 8

echo "=== Verifying USB inside LXC ==="
pct exec $CT_ID -- lsusb | grep -iE '0bda:2838|RTL|Nooelec' || {
  echo "WARNING: Dongle not visible inside LXC yet. Check $LXC_CONF and reboot again."
  exit 1
}

echo ""
echo "=== USB passthrough OK ==="
echo "Next: deploy rtlamr2mqtt (docker compose up -d rtlamr2mqtt) inside the LXC."
