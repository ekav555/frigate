# Frigate media on USB HDD

Recordings and snapshots are stored on a WD 1.8TB USB drive so they do not fill the 50GB LXC root disk.

## Layout

```
Proxmox host
  /dev/sdb1  (ext4, label frigate-storage)
       ↓ mount
  /mnt/frigate-storage
       ↓ LXC mp0 bind
  LXC 101: /mnt/frigate-storage
       ↓ docker volume
  Frigate: /media/frigate
```

| Item | Value |
|------|--------|
| Disk | WDC WD20SDZW (~1.8T), `/dev/sdb` |
| Filesystem | ext4, label `frigate-storage` |
| UUID | `6d2952d0-950d-452f-883e-38fb60281fc0` |
| Host mount | `/mnt/frigate-storage` |
| fstab | `UUID=... /mnt/frigate-storage ext4 defaults,nofail 0 2` |
| LXC bind | `mp0: /mnt/frigate-storage/media,mp=/mnt/frigate-storage` |
| Compose volume | `/mnt/frigate-storage:/media/frigate` |

## Recreate / recover

**Warning:** `mkfs.ext4` erases the disk. Only format after confirming `lsblk` shows the WD drive as `sdb` (not the Samsung system SSD `sda`).

```bash
# On Proxmox host
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL

mkfs.ext4 -L frigate-storage /dev/sdb1
mkdir -p /mnt/frigate-storage
mount /dev/sdb1 /mnt/frigate-storage

UUID=$(blkid -s UUID -o value /dev/sdb1)
grep -q frigate-storage /etc/fstab || \
  echo "UUID=$UUID /mnt/frigate-storage ext4 defaults,nofail 0 2" >> /etc/fstab

mkdir -p /mnt/frigate-storage/media
chown 100000:100000 /mnt/frigate-storage/media

grep -q frigate-storage /etc/pve/lxc/101.conf || \
  echo 'mp0: /mnt/frigate-storage/media,mp=/mnt/frigate-storage' >> /etc/pve/lxc/101.conf

pct reboot 101
pct exec 101 -- df -h /mnt/frigate-storage
```

Inside LXC, ensure `docker-compose.yml` maps `/mnt/frigate-storage:/media/frigate`, then:

```bash
cd /opt/frigate && docker compose up -d frigate
```

## Capacity notes

With three cameras recording at ~7 GiB/hour continuous, ~1.7T lasts about **10 days** full-time. Motion/event retain typically lasts longer. See Frigate System → Storage for per-camera rates.
