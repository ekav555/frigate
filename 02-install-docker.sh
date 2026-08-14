#!/bin/bash
# =============================================================
# Docker + Frigate Install - Run INSIDE the LXC container
# =============================================================
# Enter the container first:  pct enter 101
# =============================================================

set -e

echo "=== Installing Docker inside Frigate LXC ==="
echo ""

# Update and install prerequisites
echo "[1/5] Updating packages..."
apt-get update
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    vainfo \
    intel-media-va-driver

# Install Docker
echo "[2/5] Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verify Docker
echo "[3/5] Verifying Docker..."
docker --version
docker compose version

# Create Frigate directories
echo "[4/5] Creating Frigate directories..."
mkdir -p /opt/frigate/config
mkdir -p /opt/frigate/storage

# Verify GPU access
echo "[5/5] Checking GPU access..."
if [ -d /dev/dri ]; then
    echo "  /dev/dri exists:"
    ls -la /dev/dri/
    echo ""
    echo "  VA-API info:"
    vainfo 2>&1 || echo "  vainfo not working yet -- may need driver update"
else
    echo "  WARNING: /dev/dri not found! GPU passthrough may not be configured."
    echo "  Check the LXC config on the Proxmox host."
fi

echo ""
echo "=== Docker installed successfully ==="
echo ""
echo "Next steps:"
echo "  1. Copy docker-compose.yml to /opt/frigate/"
echo "  2. Copy frigate.yml to /opt/frigate/config/config.yml"
echo "  3. Run: cd /opt/frigate && docker compose up -d"
