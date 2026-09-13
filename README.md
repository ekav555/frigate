# Frigate NVR Setup on Proxmox

Security camera system using [Frigate](https://docs.frigate.video/) in a Proxmox LXC with Intel Quick Sync (QSV), plus water-meter reading via RTL-SDR in the same container.

**Session log (original build, 2026-08-16):** [SESSION-2026-08-16.md](SESSION-2026-08-16.md)

## Current host (post-migration)

| Item | Value |
|------|--------|
| Hardware | **HP ZBook Studio G5** |
| CPU | Intel **i7-8750H** (6c/12t) |
| iGPU | **UHD Graphics 630** (Quick Sync) |
| dGPU | NVIDIA Quadro P1000 Mobile (not used by Frigate) |
| RAM | **32 GB** |
| Proxmox IP | **192.168.68.40** |
| BIOS graphics | **Hybrid** (Advanced → Built-In Device Options → Graphics) |
| LAN | USB-C dock **ASIX AX88179** → `enxa0cec8ffbc4a` → `vmbr0` (no onboard Ethernet) |

Old host (**Dell**, i5-5300U / 16 GB, **192.168.68.50**) was retired after vzdump restore to `.40`.

## Architecture

```
┌────────────────────────────────────────────────────────────┐
│  Proxmox Host — HP ZBook Studio G5                         │
│  i7-8750H / UHD 630 + Quadro P1000 / 32GB                  │
│  192.168.68.40                                             │
│                                                            │
│  Host services: cloudflared (systemd, enabled)             │
│  Host harden: lid ignore, suspend masked,                  │
│               usbcore.autosuspend=-1                       │
│                                                            │
│  ┌──────────────────┐  ┌───────────────────────────────┐   │
│  │  VM 100          │  │  LXC 101 (privileged)         │   │
│  │  Home Assistant  │  │  Frigate + rtlamr2mqtt        │   │
│  │  192.168.68.120  │  │  192.168.68.121 (static)      │   │
│  │  ~ onboot        │  │  memory 6144 / cores 6        │   │
│  │                  │  │                               │   │
│  │  Mosquitto MQTT  │  │  Frigate :8971                │   │
│  │  ZHA + Sonoff    │  │  Intel QSV via renderD129     │   │
│  │  USB 10c4:ea60   │  │  RTL-SDR USB + WD bind mount  │   │
│  └──────────────────┘  └───────────────┬───────────────┘   │
│                                        │                   │
│  WD USB ──► /mnt/frigate-storage (host) ──► LXC mp0        │
└────────────────────────────────────────────────────────────┘
```

## Components

| Component | Details |
|---|---|
| **Cameras** | Reolink ×3 (`front_porch_left`, `front_porch_right`, `drive_way`) |
| **PoE Switch** | STEAMEMO 8-Port Managed Gigabit PoE+ (120W) |
| **NVR Software** | Frigate 0.17 (Docker) |
| **Hardware Decode** | Intel QSV (`preset-intel-qsv-h264`); host `renderD129` → container `renderD128` |
| **Object detect** | CPU detector, `num_threads: 4` (OpenVINO optional later) |
| **LPR** | Built-in; `drive_way` only; known plate `gray_suv` → `NDG4216` |
| **MQTT Broker** | Mosquitto on Home Assistant (`192.168.68.120:1883`) |
| **Water Meter** | rtlamr2mqtt in this LXC (USB RTL-SDR) — see [MIGRATION-WATER-METER.md](MIGRATION-WATER-METER.md) |
| **Frigate media** | WD USB → [STORAGE-USB.md](STORAGE-USB.md) |
| **Remote Access** | Cloudflare Tunnel (`cam.ekav555.com` → HTTPS `:8971`) |

## Network

| Device | IP Address |
|---|---|
| Proxmox host (ZBook) | **192.168.68.40** |
| Home Assistant VM | 192.168.68.120 |
| Frigate LXC | **192.168.68.121** (static — required for Cloudflare) |
| front_porch_left (Reolink) | 192.168.68.112 |
| front_porch_right (Reolink) | 192.168.68.125 |
| drive_way (Reolink) | 192.168.68.111 |
| Old Proxmox (retired) | 192.168.68.50 |

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

---

## Migration: Dell `.50` → ZBook `.40` (2026-09)

### What was moved

1. `vzdump` of **VM 100** (HA) and **LXC 101** (Frigate) on old host  
2. Copy dumps to `/var/lib/vz/dump/` on `.40`  
3. Restore with `--storage local-lvm` (plain `local` does not support CT volumes)  
4. Mount WD HDD (UUID `6d2952d0-950d-452f-883e-38fb60281fc0`), fstab, LXC `mp0` bind  
5. Keep guest IPs: HA `.120`, Frigate `.121`  
6. USB: RTL-SDR + `/dev/dri` into CT 101; Sonoff Zigbee (`10c4:ea60`) into VM 100  
7. Reinstall **cloudflared** on the new host (token → `/etc/cloudflared/token`, systemd enabled)

Refs kept under `/root/migration/` on the new host (`100.conf`, `101.conf`, `fstab.old`, `frigate-blkid.txt`).

### BIOS (required for Frigate QSV)

On **HP ZBook Studio G5**:

1. Esc → **F10** Setup  
2. **Advanced** → **Built-In Device Options** → **Graphics**  
3. Set **Hybrid** (not Discrete)  
4. Save & exit  

Verify both GPUs:

```bash
lspci -nn | grep -iE "vga|3d|display"
# Expect: Intel UHD Graphics 630 AND NVIDIA Quadro P1000
```

### GPU device mapping (critical)

With Hybrid enabled:

| Host node | Vendor |
|-----------|--------|
| `/dev/dri/renderD128` | **NVIDIA** (`0x10de`) |
| `/dev/dri/renderD129` | **Intel** (`0x8086`) |

Frigate presets expect `renderD128` inside the container. Compose maps:

```yaml
devices:
  - /dev/dri/renderD129:/dev/dri/renderD128
environment:
  LIBVA_DRIVER_NAME: iHD
```

```yaml
ffmpeg:
  hwaccel_args: preset-intel-qsv-h264
```

`preset-vaapi` against NVIDIA-as-`renderD128` previously broke cameras (H.264 profile errors). Soft-decode (`hwaccel_args: []`) was the interim fix until Hybrid + this mapping.

### LXC sizing on ZBook

```bash
pct set 101 -memory 6144 -cores 6
```

Compose: `shm_size: "512mb"`. Detector: `num_threads: 4`.

### Host hardening (laptop-as-server)

**Lid / sleep** — do not suspend when lid closes:

```bash
mkdir -p /etc/systemd/logind.conf.d
cat > /etc/systemd/logind.conf.d/lid.conf << 'EOF'
[Login]
HandleLidSwitch=ignore
HandleLidSwitchExternalPower=ignore
HandleLidSwitchDocked=ignore
HandleSuspendKey=ignore
HandleHibernateKey=ignore
IdleAction=ignore
EOF
systemctl restart systemd-logind
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
```

**USB autosuspend** — dock Ethernet previously hung (`usb 4-2-port1: cannot reset (err = -110)`):

```bash
echo -1 > /sys/module/usbcore/parameters/autosuspend
# Persist via GRUB: usbcore.autosuspend=-1 in GRUB_CMDLINE_LINUX_DEFAULT
update-grub
```

Keep AC power plugged in. Prefer a solid USB-C dock cable; if LAN drops again, plug the ASIX NIC directly into the laptop (bypass hub).

### Cloudflare on host

```bash
# Install package if needed, then connector token from Zero Trust dashboard:
cloudflared service uninstall   # only if reinstalling
cloudflared service install <TOKEN>
systemctl enable --now cloudflared
systemctl status cloudflared
```

Tunnel origin: **HTTPS** `192.168.68.121:8971`, **No TLS Verify**, hostname `cam.ekav555.com`.

Token lives in `/etc/cloudflared/token` — without it the unit crash-loops.

### Post-migration checklist

- [ ] HA UI `http://192.168.68.120:8123`  
- [ ] ZHA / Zigbee devices online (Sonoff passthrough)  
- [ ] Frigate UI `https://192.168.68.121:8971` — all 3 cameras  
- [ ] Bounding boxes / occupancy in HA  
- [ ] LPR on driveway (optional smoke)  
- [ ] rtlamr2mqtt water readings → MQTT → HA  
- [ ] Public URLs via Cloudflare (HA + cam)  
- [ ] Lid closed: host still reachable on `.40`  
- [ ] Old `.50` powered down after soak period  

---

## Camera stream conventions

Detect stays on H.264 sub; record on H.265 main.

| Brand | Detect | Record + live | Notes |
|-------|--------|---------------|-------|
| Reolink | `h264Preview_01_sub` | `h265Preview_01_main` | Detect uses Intel QSV H.264 |
| Amcrest | `subtype=1` Extra = **H.264** | `subtype=0` Main | Extra must not be H.265 or detect crashes |

HA `picture-entity` cards often show the detect entity — use Frigate’s UI (or a Frigate/WebRTC card) for HD live.

Full config: `config/config.yml`. Secrets via env only (see `.env.example`):

| Env var | Used for |
|---------|----------|
| `FRIGATE_RTSP_PASSWORD` | Reolink RTSP (`admin:{…}@camera`) |
| `FRIGATE_MQTT_PASSWORD` | Mosquitto (`mqtt-user`) |

On the LXC: `/opt/frigate/.env` (quote passwords that contain `$`), then `docker compose up -d`.

### Object detection / LPR / Review

Not missing: detector, detect roles, `objects.track`, MQTT.  
If live + motion work but **no bounding boxes**, loosen filters or check Debug → Regions.

**LPR:** enabled globally; active on `drive_way` only (`lpr.enabled: false` on porch cams). No Frigate+ required.

**Known plate:** `known_plates.gray_suv` → `NDG4216` / `NDG-4216` → car `sub_label: gray_suv`. Reload Frigate HA integration after changes.

**Review:** `review.alerts.labels` and `review.detections.labels` are empty so occupancy/LPR do not spam the Review timeline.

**Important:** passwords with `$` break unquoted Compose expansion:

```bash
FRIGATE_RTSP_PASSWORD='$WetherillCam$'
```

## Setup Steps (initial LXC — reference)

For a greenfield install (already done on this host via restore). Prefer static IP at create time.

### Create LXC

```bash
pct create 101 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname frigate \
  --memory 6144 \
  --swap 512 \
  --cores 6 \
  --rootfs local-lvm:50 \
  --net0 name=eth0,bridge=vmbr0,ip=192.168.68.121/24,gw=192.168.68.1 \
  --features nesting=1 \
  --unprivileged 0 \
  --onboot 1 \
  --start 0
```

### GPU + USB passthrough

```bash
cat >> /etc/pve/lxc/101.conf << 'EOF'

lxc.cgroup2.devices.allow: c 226:* rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
lxc.cgroup2.devices.allow: c 189:* rwm
lxc.mount.entry: /dev/bus/usb dev/bus/usb none bind,optional,create=dir
EOF
```

### Docker + Frigate

See [02-install-docker.sh](02-install-docker.sh). Deploy under `/opt/frigate`, set `.env`, then:

```bash
cd /opt/frigate && docker compose up -d
```

Verify Intel mapping after Hybrid BIOS:

```bash
docker inspect frigate --format '{{json .HostConfig.Devices}} shm={{.HostConfig.ShmSize}}'
# PathOnHost must be /dev/dri/renderD129 ; shm=536870912
```

### Media storage

Follow [STORAGE-USB.md](STORAGE-USB.md) before relying on long retention.

## Security Notes

- Never expose port **5000**
- Always use port **8971**
- MQTT / camera passwords live on the LXC (`.env`) — not committed
- Change default Frigate admin password after first login
- Do not commit Cloudflare tunnel tokens

## Useful Commands

```bash
# Host
pct enter 101
systemctl status cloudflared --no-pager
qm status 100
pct status 101

# Inside LXC
cd /opt/frigate && docker compose logs -f
cd /opt/frigate && docker compose restart
cd /opt/frigate && docker compose pull && docker compose up -d
pct exec 101 -- docker stats --no-stream
df -h /mnt/frigate-storage
```

## Related HA config

Home Assistant YAML lives in `ha-ekav555-config` (branch `hamain`): Cameras dashboard tab, water utility meters / derivative / automations pointed at `sensor.house_water_house_water_2`.
