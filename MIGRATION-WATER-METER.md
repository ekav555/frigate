# Water Meter Migration: Custom Add-on → rtlamr2mqtt

## Why

The custom HA add-on depended on a network hop to `rtl_tcp` on the Proxmox host.
When `rtl_tcp` crashed, the add-on entered an infinite retry loop and went silent for weeks.
rtlamr2mqtt runs **inside the Frigate LXC** with the USB dongle passed through — no network hop.

## Step A — Clean up HA (do this first)

1. **Settings → Add-ons → Water Meter Monitor**
   - Stop the add-on
   - Uninstall it
2. **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
   - Remove `ha-ekav555-water-meter` (or the GitHub URL with the PAT)
3. Optional: In MQTT Explorer / Mosquitto, clear retained topics under `rtlamr/#` and
   old discovery under `homeassistant/sensor/water_meter_75420327_*/#` if stale entities linger.
4. Archive (do not delete) the GitHub repo `ekav555/ha-ekav555-water-meter` when ready.

## Step B — Clean up Proxmox host (192.168.68.50)

Run as root on the Proxmox host (or use `04-cleanup-proxmox.sh`):

```bash
# Stop host rtl_tcp (service or manual process)
systemctl stop rtl_tcp 2>/dev/null || true
systemctl disable rtl_tcp 2>/dev/null || true
pkill -x rtl_tcp 2>/dev/null || true

# Remove host-level RTL-SDR leftovers
rm -f /etc/systemd/system/rtl_tcp.service
rm -f /etc/modprobe.d/blacklist-rtlsdr.conf
rm -f /etc/udev/rules.d/99-rtlsdr-power.rules
systemctl daemon-reload
udevadm control --reload-rules

# Confirm nothing is holding the dongle
ps aux | grep -E 'rtl_tcp|rtlamr' | grep -v grep || echo "No rtl processes"
lsusb | grep -i 0bda:2838
```

## Step C — USB passthrough to LXC 101

Run `03-usb-passthrough.sh` on the Proxmox host, or manually:

```bash
# Append to /etc/pve/lxc/101.conf if not already present:
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir

pct reboot 101
pct enter 101
lsusb | grep -i 0bda:2838   # must show the Nooelec/RTL dongle
```

## Step D — Deploy rtlamr2mqtt in the LXC

Inside LXC 101 (`pct enter 101`):

```bash
# Copy files from this repo (or recreate from examples):
#   /opt/frigate/docker-compose.yml
#   /opt/frigate/rtlamr2mqtt.yaml
#   /opt/frigate/.env   (MQTT password — already may exist for Frigate)

cd /opt/frigate
# Ensure .env has:
#   MQTT_PASSWORD=$1900Scott$   (or your Mosquitto password)
#   FRIGATE_RTSP_PASSWORD=...

docker compose up -d rtlamr2mqtt
docker logs -f rtlamr2mqtt
```

You should see meter readings for ID `75420327` and MQTT connect success.

## Step E — HA config (git pull)

On HA Studio Code Server:

```bash
cd /config && git pull origin hamain
```

Then **Developer Tools → YAML → Check Configuration → Restart**.

New entities (after MQTT discovery — names depend on HA MQTT naming):

| Entity | Role |
|--------|------|
| **`sensor.house_water_house_water_2`** | Live cumulative reading from rtlamr2mqtt (confirmed 2026-08-16) |
| `sensor.house_water_daily` | Daily usage (`utility_meter`) |
| `sensor.house_water_hourly` | Hourly usage (`utility_meter`) |
| `sensor.house_water_flow_rate` | gal/h (`derivative` in `sensors_history.yaml`) |

Point HA templates / utility meters at **`sensor.house_water_house_water_2`**, not the old
`sensor.house_water_reading` / `water_meter_75420327_*` entities.

See also [SESSION-2026-08-16.md](SESSION-2026-08-16.md).

## Step F — Verify

1. Developer Tools → States → search `house_water`
2. Dashboard Overview → Water gauges update
3. Walk through a faucet briefly → flow rate should rise
4. Automations appear under Settings → Automations (Water leak / continuous / high usage)

## Rollback

If needed: reinstall the custom add-on, restore host `rtl_tcp`, and revert the HA git commit.
Keep the archived `ha-ekav555-water-meter` repo for reference.
