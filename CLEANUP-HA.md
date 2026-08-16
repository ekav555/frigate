# HA cleanup checklist — Water Meter Monitor add-on

Do these in the Home Assistant UI (cannot be done from this repo alone):

## 1. Stop and uninstall the add-on

1. Open **Settings → Add-ons**
2. Open **Water Meter Monitor**
3. Click **Stop**
4. Click **Uninstall**

## 2. Remove the private add-on repository

1. **Settings → Add-ons → Add-on Store**
2. Top-right **⋮ → Repositories**
3. Remove `ha-ekav555-water-meter` / the GitHub URL that pointed at that repo
4. Save

## 3. Optional MQTT cleanup

If old entities linger after uninstall:

1. **Settings → Devices & Services → MQTT → Configure → Re-configure** or use MQTT Explorer
2. Delete retained topics matching:
   - `homeassistant/sensor/water_meter_75420327_*/config`
   - Old `rtlamr/...` payloads from the custom add-on (rtlamr2mqtt will republish)

## 4. Pull HA config changes

In Studio Code Server on HA:

```bash
cd /config
git pull origin hamain
```

Then **Developer Tools → YAML → Check Configuration → Restart Home Assistant**.

## 5. Confirm new entities

After rtlamr2mqtt is running, search Developer Tools → States for:

- `sensor.house_water_house_water_2` — live reading (rtlamr2mqtt)
- `sensor.house_water_daily`
- `sensor.house_water_hourly`
- `sensor.house_water_flow_rate`

Delete stale MQTT device **Water Meter 75420327** if `sensor.water_meter_75420327_*` still appear.

## 6. Archive the old GitHub repo (later)

On GitHub: **ekav555/ha-ekav555-water-meter → Settings → Archive repository**
(Do not delete yet — keep as reference.)
