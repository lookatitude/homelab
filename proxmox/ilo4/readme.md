##✅ ILO4 Fan control on proxmox:

### the config in the script

```bash
#!/bin/bash

# === CONFIGURATION ===

ILO_HOST="ilo4-hostname-or-ip"
ILO_USER="admin"

USE_SSH_PASS=true            # Set to false to use SSH key auth
ILO_PASS="yourpassword"      # Required only if USE_SSH_PASS=true

FAN_COUNT=6                  # Number of fans (fan 0 to FAN_COUNT-1)
GLOBAL_MIN_SPEED=60         # Minimum fan speed % for each fan
PID_MIN_LOW=1600            # Minimum low RPM for all PIDs
DISABLED_SENSORS=(07FB00 35 38)  # Sensors to turn off /us  

# ========================
```

### Make it executable:
``` chmod +x /usr/local/bin/ilo4-fan-config.sh ```

Create a systemd Service: /etc/systemd/system/ilo4-fan-config.service

```ini
[Unit]
Description=ILO4 Fan Configuration Script
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/ilo4-fan-control.sh

[Install]
WantedBy=multi-user.target
```
### Setup Steps on Proxmox
Run these commands:

```bash
# Place the script and make it executable
nano /usr/local/bin/ilo4-fan-control.sh
chmod +x /usr/local/bin/ilo4-fan-control.sh

# Create and enable the service
nano /etc/systemd/system/ilo4-fan-control.service
systemctl daemon-reload
systemctl enable ilo4-fan-control.service
```
You can test the script manually first:

```bash
/usr/local/bin/ilo4-fan-control.sh
```


Then reboot to confirm it runs automatically.