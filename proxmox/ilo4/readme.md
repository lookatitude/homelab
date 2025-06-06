# iLO4 Fan Control for Proxmox/Debian

A comprehensive fan control solution for HP servers with iLO4 that automatically manages fan speeds and provides dynamic temperature-based control.

## Features

- **Automatic Fan Configuration**: Sets minimum fan speeds and disables problematic sensors on startup
- **Dynamic Temperature Control**: Adjusts fan speeds based on CPU temperatures with configurable thresholds
- **SSH-based Remote Control**: Manages fans through iLO4's SSH interface
- **Systemd Service Integration**: Runs automatically on boot and can be managed with standard systemd commands
- **Comprehensive Logging**: Detailed logging for troubleshooting and monitoring
- **Retry Logic**: Robust error handling with automatic retries for network issues

## Quick Installation

Run this one-liner to download and install everything automatically:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)"
```

The installation script will:
1. Ask for your iLO4 connection details (IP, username, password)
2. Configure fan settings with sensible defaults (you can customize them)
3. Install all required dependencies
4. Download and configure the fan control script
5. Set up the systemd service
6. Enable automatic startup on boot

## Manual Installation

If you prefer to install manually:

### 1. Install Dependencies

```bash
sudo apt update
sudo apt install -y sshpass openssh-client wget curl lm-sensors jq
```

### 2. Download and Configure

```bash
# Download the script
sudo wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/ilo4-fan-control.sh -O /usr/local/bin/ilo4-fan-control.sh
sudo chmod +x /usr/local/bin/ilo4-fan-control.sh

# Download the service file
sudo wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/ilo4-fan-control.service -O /etc/systemd/system/ilo4-fan-control.service
```

### 3. Configure the Script

Edit `/usr/local/bin/ilo4-fan-control.sh` and modify these settings:

```bash
# === CONFIGURATION ===
ILO_HOST="10.10.10.2"        # Your iLO IP or hostname
ILO_USER="Administrator"      # iLO username
ILO_PASS="your_password"      # iLO password

FAN_COUNT=6                   # Number of fans (usually 6)
GLOBAL_MIN_SPEED=60          # Minimum fan speed (0-255)
PID_MIN_LOW=1600             # Minimum PID low value
DISABLED_SENSORS=(07FB00 35 38)  # Sensors to disable

# Dynamic control settings
ENABLE_DYNAMIC_CONTROL=true  # Enable temperature-based control
MONITORING_INTERVAL=30       # Check temperature every 30 seconds
CPU1_FANS=(3 4 5)           # Fans for CPU1 (rear fans)
CPU2_FANS=(0 1 2)           # Fans for CPU2 (front fans)

# Temperature thresholds and fan speeds
declare -A TEMP_THRESHOLDS=(
    [67]=255    # Emergency cooling
    [58]=39     # High temperature
    [54]=38     # Medium-high
    [52]=34     # Medium
    [50]=32     # Low-medium
    [0]=30      # Default/idle
)
```

### 4. Enable the Service

```bash
sudo systemctl daemon-reload
sudo systemctl enable ilo4-fan-control.service
sudo systemctl start ilo4-fan-control.service
```

## Configuration Options

### Fan Control Settings

- **FAN_COUNT**: Total number of fans in your server (typically 6)
- **GLOBAL_MIN_SPEED**: Minimum fan speed (0-255, where 255 is maximum)
- **PID_MIN_LOW**: Minimum low value for PID controllers
- **DISABLED_SENSORS**: Array of sensor IDs to disable (prevents thermal shutdowns)

### Dynamic Control

- **ENABLE_DYNAMIC_CONTROL**: Set to `false` to disable temperature monitoring
- **MONITORING_INTERVAL**: How often to check temperatures (seconds)
- **CPU1_FANS/CPU2_FANS**: Which fans are controlled by each CPU temperature

### Temperature Thresholds

The script uses these default temperature thresholds:
- **67°C+**: Emergency cooling (fan speed 255)
- **58°C+**: High temperature (fan speed 39)
- **54°C+**: Medium-high (fan speed 38)
- **52°C+**: Medium (fan speed 34)
- **50°C+**: Low-medium (fan speed 32)
- **Below 50°C**: Idle (fan speed 30)

## Service Management

### Common Commands

```bash
# Check service status
sudo systemctl status ilo4-fan-control

# Start the service
sudo systemctl start ilo4-fan-control

# Stop the service
sudo systemctl stop ilo4-fan-control

# Restart after configuration changes
sudo systemctl restart ilo4-fan-control

# View real-time logs
sudo journalctl -u ilo4-fan-control -f

# View script logs
sudo tail -f /var/log/ilo4-fan-control.log
```

### Testing

Test the script manually before enabling the service:

```bash
sudo /usr/local/bin/ilo4-fan-control.sh
```

## How It Works

1. **Initialization**: On startup, the script connects to your iLO4 via SSH
2. **Fan Setup**: Sets minimum fan speeds and disables problematic sensors
3. **Temperature Monitoring**: If enabled, continuously monitors CPU temperatures
4. **Dynamic Adjustment**: Adjusts fan speeds based on temperature thresholds
5. **Logging**: All activities are logged for monitoring and troubleshooting

## Troubleshooting

### Connection Issues

If you see SSH connection failures:
1. Verify iLO IP address and credentials
2. Ensure iLO SSH is enabled
3. Check network connectivity: `ping your-ilo-ip`

### Service Not Starting

```bash
# Check service logs
sudo journalctl -u ilo4-fan-control -n 50

# Check script logs
sudo cat /var/log/ilo4-fan-control.log

# Test script manually
sudo /usr/local/bin/ilo4-fan-control.sh
```

### Temperature Monitoring Issues

If running remotely (not on the server itself):
- Temperature monitoring will be disabled automatically
- Only initial fan setup will be performed
- This is normal behavior for remote management

## File Locations

- **Script**: `/usr/local/bin/ilo4-fan-control.sh`
- **Service**: `/etc/systemd/system/ilo4-fan-control.service`
- **Logs**: `/var/log/ilo4-fan-control.log`

## Security Notes

- The script stores iLO credentials in plain text
- Ensure proper file permissions (600) for the script
- Consider using SSH keys instead of passwords for enhanced security

## Compatibility

- **Servers**: HP ProLiant servers with iLO4
- **OS**: Proxmox VE, Debian, Ubuntu
- **Requirements**: SSH access to iLO4, `sshpass` package

## Support

For issues, questions, or contributions, please use the GitHub repository where this script is hosted.