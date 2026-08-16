# Frigate NVR Setup on Proxmox

Security camera system using [Frigate](https://docs.frigate.video/) running in a Proxmox LXC container with Intel Quick Sync hardware video decoding.

## Architecture

```
┌──────────────────────────────────────────┐
│         Proxmox Host (bare metal)        │
│         Intel i5-5300U / 16GB RAM        │
│         192.168.68.50                    │
│                                          │
│  ┌──────────────┐  ┌─────────────────┐   │
│  │  VM 100      │  │  LXC 101        │   │
│  │  Home Assist.│  │  Frigate + SDR  │   │
│  │  .68.120     │  │  .68.121        │   │
│  │              │  │                 │   │
│  │  - Mosquitto │  │  - Frigate      │   │
│  │    (MQTT)    │  │  - rtlamr2mqtt  │   │
│  └──────────────┘  │    (RTL-SDR USB)│   │
│                    └─────────────────┘   │
│                                          │
│  Host services:                          │
│  - cloudflared                           │
└──────────────────────────────────────────┘
```

See also [MIGRATION-WATER-METER.md](MIGRATION-WATER-METER.md) for moving off the
custom Water Meter Monitor add-on onto rtlamr2mqtt in this LXC.

## Components

| Component | Details |
|---|---|
| **Cameras** | Reolink RLC-810A (4K PoE) |
| **PoE Switch** | STEAMEMO 8-Port Managed Gigabit PoE+ (120W) |
| **NVR Software** | Frigate (Docker container) |
| **Hardware Decode** | Intel Quick Sync (VAAPI) via /dev/dri passthrough |
| **MQTT Broker** | Mosquitto on Home Assistant (192.168.68.120:1883) |
| **Water Meter** | rtlamr2mqtt in this LXC (USB RTL-SDR passthrough) |
| **Remote Access** | Cloudflare Tunnel (`cam.ekav555.com`) |

## Network

| Device | IP Address |
|---|---|
| Proxmox host | 192.168.68.50 |
| Home Assistant VM | 192.168.68.120 |
| Frigate LXC | 192.168.68.121 |

## Ports

| Port | Description |
|---|---|
| **8971** | Authenticated UI and API (use this for all access) |
| 5000 | Internal unauthenticated port (DO NOT expose externally) |
| 8554 | RTSP restream |
| 8555 | WebRTC |

## Setup Steps

### Step 1: Create LXC on Proxmox

Run on the Proxmox host as root:

```bash
# Download Debian 12 template
pveam update
pveam download local debian-12-standard_12.12-1_amd64.tar.zst

# Create privileged LXC container
pct create 101 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname frigate \
  --memory 3072 \
  --swap 512 \
  --cores 2 \
  --rootfs local-lvm:50 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --features nesting=1 \
  --unprivileged 0 \
  --onboot 1 \
  --start 0
```

### Step 2: Add GPU Passthrough

```bash
cat >> /etc/pve/lxc/101.conf << 'EOF'

lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
EOF
```

### Step 3: Start and Enter Container

```bash
pct start 101
pct enter 101
```

Verify GPU access:

```bash
ls -la /dev/dri/
# Should show card1 and renderD128
```

### Step 4: Install Docker

Inside the LXC container:

```bash
apt-get update && apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
```

### Step 5: Deploy Frigate

```bash
mkdir -p /opt/frigate/config /opt/frigate/storage
```

Copy `docker-compose.yml` to `/opt/frigate/` and `config/config.yml` to `/opt/frigate/config/config.yml`.

Update `config.yml` with your actual MQTT password (replace `{MQTT_PASSWORD}`).

```bash
cd /opt/frigate
docker compose up -d
```

### Step 6: Verify

```bash
# Check Frigate is running
docker logs frigate 2>&1 | tail -20

# Check GPU access inside container
docker exec frigate ls -la /dev/dri/
```

Access the UI at `https://192.168.68.121:8971` (requires login).

### Step 7: Cloudflare Tunnel (Remote Access)

In Cloudflare Zero Trust dashboard, add a public hostname:

- **Subdomain**: frigate
- **Domain**: ekav555.com
- **Service Type**: HTTPS
- **URL**: 192.168.68.121:8971
- **TLS Settings**: No TLS Verify (self-signed cert)

## Adding a Camera

When a new camera arrives:

1. Connect camera to PoE switch
2. Find its IP using the Reolink app
3. Set a static IP and admin password on the camera
4. **Set main stream to H.264** (not H.265) in camera settings for best Quick Sync compatibility
5. Edit `/opt/frigate/config/config.yml`:
   - Update the camera's RTSP IP and password
   - Set `enabled: true`
6. Restart Frigate: `cd /opt/frigate && docker compose restart`

### Reolink RLC-810A RTSP URLs

```
Main (4K recording):  rtsp://admin:<password>@<camera-ip>:554/h264Preview_01_main
Sub (detection):      rtsp://admin:<password>@<camera-ip>:554/h264Preview_01_sub
```

## Security Notes

- **Never expose port 5000** externally -- it grants unauthenticated admin access
- Always use port **8971** for browser/remote access
- MQTT password is stored in `config.yml` on the LXC, not in this repo
- Keep Frigate updated to patch vulnerabilities (CVE-2026-25643 affects < 0.16.4)
- Change the default admin password after first login

## Useful Commands

```bash
# Enter the Frigate LXC from Proxmox host
pct enter 101

# View Frigate logs
cd /opt/frigate && docker compose logs -f

# Restart Frigate after config changes
cd /opt/frigate && docker compose restart

# Update Frigate to latest version
cd /opt/frigate && docker compose pull && docker compose up -d

# Check Frigate version
docker exec frigate cat /opt/frigate/frigate/VERSION
```
