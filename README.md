# Frigate NVR Setup on Proxmox

Security camera system using [Frigate](https://docs.frigate.video/) in a Proxmox LXC with Intel Quick Sync (VAAPI), plus water-meter reading via RTL-SDR in the same container.

**Session log (commands from 2026-08-16):** [SESSION-2026-08-16.md](SESSION-2026-08-16.md)

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
│  │  .68.120     │  │  .68.121 static │   │
│  │              │  │                 │   │
│  │  - Mosquitto │  │  - Frigate      │   │
│  │    (MQTT)    │  │  - rtlamr2mqtt  │   │
│  └──────────────┘  │    (RTL-SDR USB)│   │
│                    └────────┬────────┘   │
│                             │            │
│  USB WD 1.8TB ──► /mnt/frigate-storage   │
│  Host services: cloudflared              │
└──────────────────────────────────────────┘
```

## Components

| Component | Details |
|---|---|
| **Cameras** | Reolink ×3 (`front_porch_left`, `front_porch_right`, `drive_way`) |
| **PoE Switch** | STEAMEMO 8-Port Managed Gigabit PoE+ (120W) |
| **NVR Software** | Frigate (Docker) |
| **Hardware Decode** | Intel Quick Sync (VAAPI) via `/dev/dri` |
| **MQTT Broker** | Mosquitto on Home Assistant (`192.168.68.120:1883`) |
| **Water Meter** | rtlamr2mqtt in this LXC (USB RTL-SDR) — see [MIGRATION-WATER-METER.md](MIGRATION-WATER-METER.md) |
| **Frigate media** | WD 1.8TB USB → [STORAGE-USB.md](STORAGE-USB.md) |
| **Remote Access** | Cloudflare Tunnel (`cam.ekav555.com` → HTTPS `:8971`) |

## Network

| Device | IP Address |
|---|---|
| Proxmox host | 192.168.68.50 |
| Home Assistant VM | 192.168.68.120 |
| Frigate LXC | **192.168.68.121** (static — required for Cloudflare) |
| front_porch_left (Reolink) | 192.168.68.124 |
| front_porch_right (Reolink) | set in live Frigate config |
| drive_way (Reolink) | set in live Frigate config |

## Ports

| Port | Description |
|---|---|
| **8971** | Authenticated UI and API (use for browser, Cloudflare, HA) |
| 5000 | Unauthenticated — **do not publish** in compose |
| 8554 | RTSP restream |
| 8555 | WebRTC |

## Docs in this repo

| File | Purpose |
|------|---------|
| [SESSION-2026-08-16.md](SESSION-2026-08-16.md) | Full command log for the Aug 16 camera + water + USB work |
| [STORAGE-USB.md](STORAGE-USB.md) | WD HDD mount / LXC bind / compose volume |
| [MIGRATION-WATER-METER.md](MIGRATION-WATER-METER.md) | Custom add-on → rtlamr2mqtt |
| [CLEANUP-HA.md](CLEANUP-HA.md) | HA UI steps to remove old water add-on |
| `01`–`05` `*.sh` | Host/LXC helper scripts |

## Camera stream conventions

Broadwell Quick Sync does **not** handle HEVC well on the detect path.

| Brand | Detect | Record + live | Notes |
|-------|--------|---------------|-------|
| Reolink | `h264Preview_01_sub` | `h265Preview_01_main` | go2rtc restream; `live.streams` Main/Sub |
| Amcrest | `subtype=1` Extra = **H.264** | `subtype=0` Main | Extra must not be H.265 or detect crashes |

Without go2rtc, Frigate live falls back to **jsmpeg of the 640p detect feed** (much softer than the Reolink app). With go2rtc + `live.streams`, pick **Main** in the Frigate player for HD live; detect stays on Sub.

HA `picture-entity` cards still often show the detect entity — use Frigate’s own UI (or a Frigate/WebRTC card) for Reolink-app-like live quality.

Template: `config/config.yml` (passwords via `{FRIGATE_RTSP_PASSWORD}` / env — live secrets stay on the LXC).

## Setup Steps (initial LXC)

### Step 1: Create LXC on Proxmox

```bash
pveam update
pveam download local debian-12-standard_12.12-1_amd64.tar.zst

pct create 101 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname frigate \
  --memory 3072 \
  --swap 512 \
  --cores 2 \
  --rootfs local-lvm:50 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.68.121/24,gw=192.168.68.1 \
  --features nesting=1 \
  --unprivileged 0 \
  --onboot 1 \
  --start 0
```

Prefer static IP at create time (DHCP previously moved this LXC and broke Cloudflare).

### Step 2: GPU + USB passthrough

```bash
cat >> /etc/pve/lxc/101.conf << 'EOF'

lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
EOF
```

### Step 3–5: Docker + Frigate

See [02-install-docker.sh](02-install-docker.sh). Deploy `docker-compose.yml` + `config/` under `/opt/frigate`, set `.env`, then:

```bash
cd /opt/frigate && docker compose up -d
```

### Media storage

Follow [STORAGE-USB.md](STORAGE-USB.md) before relying on long retention.

### Cloudflare

- Type **HTTPS**, URL `192.168.68.121:8971`, **No TLS Verify**
- Hostname: `cam.ekav555.com`

## Security Notes

- Never expose port **5000**
- Always use port **8971**
- MQTT / camera passwords live on the LXC (`.env`, live `config.yml`) — not committed
- Change default Frigate admin password after first login

## Useful Commands

```bash
pct enter 101
cd /opt/frigate && docker compose logs -f
cd /opt/frigate && docker compose restart
cd /opt/frigate && docker compose pull && docker compose up -d
pct exec 101 -- docker stats --no-stream
df -h /mnt/frigate-storage
```

## Related HA config

Home Assistant YAML lives in `ha-ekav555-config` (branch `hamain`): Cameras dashboard tab, water utility meters / derivative / automations pointed at `sensor.house_water_house_water_2`.
