#!/bin/bash
# =============================================================
# Frigate LXC Setup - Run this on the Proxmox host (as root)
# =============================================================
# Creates a privileged Debian 12 LXC with GPU passthrough
# for Intel Quick Sync hardware video decoding.
# =============================================================

set -e

CT_ID=101
CT_HOSTNAME="frigate"
CT_MEMORY=3072
CT_SWAP=512
CT_CORES=2
CT_DISK=50
CT_BRIDGE="vmbr0"
TEMPLATE="debian-12-standard_12.12-1_amd64.tar.zst"

echo "=== Frigate LXC Setup ==="
echo ""

# Check if CT ID is already in use
if pct status $CT_ID &>/dev/null; then
    echo "ERROR: Container ID $CT_ID already exists!"
    echo "Either destroy it first (pct destroy $CT_ID) or change CT_ID in this script."
    exit 1
fi

# Download template if not already available
echo "[1/4] Downloading Debian 12 template..."
pveam update
if ! pveam list local | grep -q "$TEMPLATE"; then
    pveam download local $TEMPLATE
else
    echo "  Template already downloaded."
fi

# Create the container
echo "[2/4] Creating LXC container $CT_ID ($CT_HOSTNAME)..."
pct create $CT_ID local:vztmpl/$TEMPLATE \
    --hostname $CT_HOSTNAME \
    --memory $CT_MEMORY \
    --swap $CT_SWAP \
    --cores $CT_CORES \
    --rootfs local-lvm:$CT_DISK \
    --net0 name=eth0,bridge=$CT_BRIDGE,ip=dhcp \
    --features nesting=1 \
    --unprivileged 0 \
    --onboot 1 \
    --start 0

echo "  Container created."

# Add GPU passthrough to LXC config
echo "[3/4] Configuring GPU passthrough for Intel Quick Sync..."
LXC_CONF="/etc/pve/lxc/${CT_ID}.conf"

cat >> "$LXC_CONF" << 'EOF'

# Intel GPU passthrough for hardware video decoding
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF

echo "  GPU passthrough configured."

# Start the container
echo "[4/4] Starting container..."
pct start $CT_ID
sleep 5

echo ""
echo "=== LXC container $CT_ID ($CT_HOSTNAME) is running ==="
echo ""
echo "Get the container's IP:"
echo "  pct exec $CT_ID -- ip addr show eth0"
echo ""
echo "Enter the container:"
echo "  pct enter $CT_ID"
echo ""
echo "Next step: Run 02-install-docker.sh inside the container."
