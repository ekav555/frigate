#!/bin/bash
# =============================================================
# Deploy / update rtlamr2mqtt inside Frigate LXC
# Run INSIDE LXC 101:  pct enter 101
# =============================================================
set -e

cd /opt/frigate

if [ ! -f rtlamr2mqtt.yaml ]; then
  if [ -f rtlamr2mqtt.yaml.example ]; then
    cp rtlamr2mqtt.yaml.example rtlamr2mqtt.yaml
    echo "Created rtlamr2mqtt.yaml from example."
    echo "EDIT mqtt.password BEFORE starting:"
    echo "  nano /opt/frigate/rtlamr2mqtt.yaml"
    exit 1
  else
    echo "ERROR: rtlamr2mqtt.yaml missing. Copy from frigate-setup repo."
    exit 1
  fi
fi

if grep -q 'CHANGE_ME' rtlamr2mqtt.yaml; then
  echo "ERROR: Set mqtt.password in rtlamr2mqtt.yaml (still CHANGE_ME)."
  exit 1
fi

echo "=== USB check ==="
lsusb | grep -iE '0bda:2838|RTL|Nooelec' || {
  echo "ERROR: RTL-SDR not visible in this LXC. Run 03-usb-passthrough.sh on Proxmox host first."
  exit 1
}

echo "=== Starting rtlamr2mqtt ==="
docker compose up -d rtlamr2mqtt
sleep 3
docker compose ps rtlamr2mqtt
echo ""
echo "=== Recent logs ==="
docker logs rtlamr2mqtt 2>&1 | tail -40
echo ""
echo "Follow logs with:  docker logs -f rtlamr2mqtt"
