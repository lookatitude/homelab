# HP iLO4 Fan Control System for ProLiant Servers

A comprehensive, configurable fan control solution for HP servers with iLO4 that provides both automatic temperature-based control and manual management capabilities.

## 🔥 Features

- **🚀 Automatic Installation**: One-liner installer with intelligent configuration loading
- **🌡️ Dynamic Temperature Control**: Configurable temperature thresholds and fan speeds
- **🔧 Manual Control Interface**: Interactive and command-line manual fan management
- **⚙️ Advanced Configuration**: Fully configurable temperature steps and thresholds
- **📊 Comprehensive Logging**: Detailed logging with configurable levels and log rotation
- **🔄 Systemd Integration**: Runs as a systemd service with automatic startup
- **🛡️ Robust Error Handling**: Retry logic, emergency protection, and failsafe modes
- **📋 Threshold Management**: Add/remove temperature steps dynamically

## 🚀 Quick Installation

### One-Line Auto-Install
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --install
```

### One-Line Update
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --update
```

> **Note:** The `--` is required to ensure arguments are passed to the script, not to bash itself.

### What the installer does:
1. **Detects existing configuration** and loads current settings as defaults (if re-running)
2. Prompts for iLO4 connection details (IP, username, password)
3. Configures fan settings with sensible defaults or existing values
4. Installs all required dependencies automatically
5. Downloads and configures all scripts and service files
6. Sets up systemd service with automatic startup
7. Tests the configuration and connection

### After installation
- The `ilo4-fan-control` service will be started automatically.
- To check status: `sudo systemctl status ilo4-fan-control`
- To manually control fans: `sudo ilo4-fan-control-manual.sh --interactive`
- To update: use the update one-liner above.

### Re-running the installer
When you run the installer on an existing installation, it will:
- **Load your current configuration** as defaults for all prompts
- Allow you to modify any settings while keeping others unchanged
- Preserve your existing configuration and only update what you change
- Test the new configuration before applying changes

## 🔄 Quick Update

To update to the latest version, run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --update
```

## 📋 System Requirements

- **Servers**: HP ProLiant servers with iLO4
- **OS**: Proxmox VE, Debian, Ubuntu (systemd-based distributions)
- **Network**: SSH access to iLO4 interface
- **Dependencies**: Automatically installed by the installer

## 🎛️ Usage Guide

### 🤖 Automatic Mode (Recommended)

The system runs automatically as a systemd service after installation:

```bash
# Check service status
sudo systemctl status ilo4-fan-control

# View real-time logs
sudo journalctl -u ilo4-fan-control -f

# View detailed script logs
sudo tail -f /var/log/ilo4-fan-control.log
```

### 🔧 Manual Control

The system includes a comprehensive manual control interface:

#### Interactive Mode
```bash
sudo ilo4-fan-control-manual.sh --interactive
```
Provides a menu-driven interface for:
- Viewing current fan status and temperatures
- Setting individual fan speeds
- Setting all fans to the same speed
- Resetting to safe defaults
- Emergency maximum speed mode

#### Command Line Operations
```bash
# Show current fan status
sudo ilo4-fan-control-manual.sh --status

# Set specific fan speed (fan 3 to speed 128)
sudo ilo4-fan-control-manual.sh --set-speed 3 128

# Set all fans to same speed
sudo ilo4-fan-control-manual.sh --set-all 100

# Reset to safe defaults
sudo ilo4-fan-control-manual.sh --reset

# Emergency mode (maximum speed)
sudo ilo4-fan-control-manual.sh --emergency

# Test iLO connection
sudo ilo4-fan-control-manual.sh --test
```

### ⚙️ Configuration Management

#### Using the Configuration Script
```bash
# List current temperature steps
sudo set-thresholds.sh --list-temp-steps

# Add a new temperature step (85°C with fan speed 180)
sudo set-thresholds.sh --add-temp-step 85 180

# Remove a temperature step
sudo set-thresholds.sh --remove-temp-step 85

# Show all current thresholds
sudo set-thresholds.sh --show-thresholds

# Interactive threshold management
sudo set-thresholds.sh --interactive
```

#### Direct Configuration File Editing
```bash
# Edit the main configuration file
sudo nano /etc/ilo4-fan-control/ilo4-fan-control.conf

# Restart service after changes
sudo systemctl restart ilo4-fan-control
```

## 📊 Configuration Options

### 🌡️ Temperature Thresholds (New Enhanced System)

The system uses configurable temperature steps with corresponding fan speeds:

**Default Configuration:**
- **90°C**: Fan speed 255 (Maximum cooling)
- **80°C**: Fan speed 200 (High cooling)
- **70°C**: Fan speed 150 (Medium-high cooling)
- **60°C**: Fan speed 100 (Medium cooling)
- **50°C**: Fan speed 75 (Low cooling)
- **Below 50°C**: Fan speed 50 (Idle/minimum)

**Emergency Protection:**
- **Above MAX_TEMP_CPU (default 80°C)**: All fans to maximum speed (255)
- **Temperature read failures**: Automatic fallback to safe speeds

### 🔧 Core Settings

```bash
# iLO Connection
ILO_HOST="192.168.1.100"        # iLO IP or hostname
ILO_USER="Administrator"         # iLO username
ILO_PASS="your_password"        # iLO password

# Fan Configuration
FAN_COUNT=6                     # Number of fans (typically 6)
GLOBAL_MIN_SPEED=60            # Minimum fan speed (0-255)
PID_MIN_LOW=1600               # Minimum PID low value
DISABLED_SENSORS=(07FB00 35 38) # Sensors to disable

# Dynamic Control
ENABLE_DYNAMIC_CONTROL=true    # Enable temperature-based control
MONITORING_INTERVAL=30         # Temperature check interval (seconds)
CPU1_FANS=(3 4 5)             # Fans controlled by CPU1 temp
CPU2_FANS=(0 1 2)             # Fans controlled by CPU2 temp

# Temperature Steps (configurable)
TEMP_STEPS=(90 80 70 60 50)    # Temperature thresholds in °C
TEMP_THRESHOLD_90=255          # Fan speed for 90°C+
TEMP_THRESHOLD_80=200          # Fan speed for 80°C+
TEMP_THRESHOLD_70=150          # Fan speed for 70°C+
TEMP_THRESHOLD_60=100          # Fan speed for 60°C+
TEMP_THRESHOLD_50=75           # Fan speed for 50°C+
TEMP_THRESHOLD_DEFAULT=50      # Default fan speed

# Advanced Settings
MAX_TEMP_CPU=80               # Emergency temperature threshold
LOG_LEVEL="INFO"              # DEBUG, INFO, WARN, ERROR
CONNECTION_TIMEOUT=30         # SSH connection timeout
COMMAND_RETRIES=3             # Number of retry attempts
```

### 📝 Logging Configuration

```bash
LOG_FILE="/var/log/ilo4-fan-control.log"
MAX_LOG_SIZE="50M"
LOG_RETENTION_DAYS=30
```

## 🚨 Service Management

### 🔄 Common Commands

```bash
# Service Control
sudo systemctl start ilo4-fan-control      # Start service
sudo systemctl stop ilo4-fan-control       # Stop service
sudo systemctl restart ilo4-fan-control    # Restart service
sudo systemctl reload ilo4-fan-control     # Reload configuration
sudo systemctl enable ilo4-fan-control     # Enable auto-start
sudo systemctl disable ilo4-fan-control    # Disable auto-start

# Status and Monitoring
sudo systemctl status ilo4-fan-control     # Service status
sudo journalctl -u ilo4-fan-control -f     # Real-time system logs
sudo journalctl -u ilo4-fan-control -n 50  # Last 50 log entries
sudo tail -f /var/log/ilo4-fan-control.log # Real-time script logs

# Log Analysis
sudo grep "ERROR" /var/log/ilo4-fan-control.log    # Show errors
sudo grep "EMERGENCY" /var/log/ilo4-fan-control.log # Show emergency events
```

### 🧪 Testing and Troubleshooting

```bash
# Test script manually (without systemd)
sudo /usr/local/bin/ilo4-fan-control.sh

# Test with debug logging
sudo LOG_LEVEL=DEBUG /usr/local/bin/ilo4-fan-control.sh

# Validate configuration
sudo bash -n /usr/local/bin/ilo4-fan-control.sh

# Test iLO connection only
sudo ilo4-fan-control-manual.sh --test

# Check configuration file syntax
sudo bash -n /etc/ilo4-fan-control/ilo4-fan-control.conf
```

## 🔧 Advanced Usage

### 🎯 Custom Temperature Profiles

Create custom temperature profiles for different workloads:

```bash
# Gaming/High Performance Profile
sudo set-thresholds.sh --add-temp-step 85 220
sudo set-thresholds.sh --add-temp-step 75 180
sudo set-thresholds.sh --set-threshold 60 120
sudo systemctl restart ilo4-fan-control

# Quiet/Office Profile  
sudo set-thresholds.sh --set-threshold 90 200
sudo set-thresholds.sh --set-threshold 80 150
sudo set-thresholds.sh --set-threshold 70 100
sudo systemctl restart ilo4-fan-control
```

### 📊 Monitoring Integration

```bash
# Export current status for monitoring systems
sudo ilo4-fan-control-manual.sh --status --json > /tmp/fan-status.json

# Create custom monitoring script
cat << 'EOF' > /usr/local/bin/fan-monitor.sh
#!/bin/bash
# Custom fan monitoring script
STATUS=$(sudo ilo4-fan-control-manual.sh --status)
echo "$(date): $STATUS" >> /var/log/fan-monitoring.log
EOF
chmod +x /usr/local/bin/fan-monitor.sh
```

### 🔒 Security Considerations

```bash
# Secure the configuration file
sudo chmod 600 /etc/ilo4-fan-control/ilo4-fan-control.conf
sudo chown root:root /etc/ilo4-fan-control/ilo4-fan-control.conf

# Use SSH key authentication instead of passwords
# Edit configuration file and set:
# USE_SSH_PASS=false
# Then set up SSH key authentication to iLO
```

## 🏗️ System Architecture

### 📁 File Locations

```
/usr/local/bin/
├── ilo4-fan-control.sh           # Main service script
├── ilo4-fan-control-manual.sh    # Manual control interface
└── set-thresholds.sh             # Threshold management script

/etc/ilo4-fan-control/
└── ilo4-fan-control.conf         # Main configuration file

/etc/systemd/system/
└── ilo4-fan-control.service      # Systemd service definition

/var/log/
└── ilo4-fan-control.log          # Script execution logs
```

### 🔄 How It Works

1. **Initialization**: Service starts and loads configuration
2. **iLO Connection**: Establishes SSH connection to iLO4
3. **Fan Setup**: Sets minimum speeds and disables problematic sensors
4. **Temperature Monitoring**: Continuously reads CPU temperatures (if enabled)
5. **Dynamic Control**: Adjusts fan speeds based on configurable temperature thresholds
6. **Emergency Protection**: Activates maximum cooling if temperatures exceed safe limits
7. **Logging**: Records all activities for monitoring and troubleshooting

### 🛡️ Safety Features

- **Emergency Protection**: Automatic maximum fan speed if CPU temperature exceeds safe limits
- **Failsafe Mode**: Falls back to safe defaults if temperature readings fail
- **Connection Monitoring**: Automatic reconnection on SSH failures
- **Sensor Validation**: Validates temperature readings for sanity
- **Configuration Validation**: Checks configuration file integrity on startup

## 🚨 Troubleshooting Guide

### 🔌 Connection Issues

**Problem**: SSH connection failures
```bash
# Check network connectivity
ping your-ilo-ip

# Test SSH manually
ssh Administrator@your-ilo-ip

# Check iLO SSH settings via web interface
# iLO Web UI → Network → SSH Settings
```

**Problem**: Authentication failures
```bash
# Verify credentials in configuration
sudo grep -E "(ILO_HOST|ILO_USER)" /etc/ilo4-fan-control/ilo4-fan-control.conf

# Test credentials manually
sudo ilo4-fan-control-manual.sh --test
```

### 🌡️ Temperature Monitoring Issues

**Problem**: Temperature readings show 0°C
```bash
# Check if running on the actual server (not remotely)
hostname

# Install temperature monitoring tools
sudo apt install lm-sensors
sudo sensors-detect

# Test temperature reading
sensors
```

**Problem**: No temperature data available
- This is normal when running remotely
- Only initial fan setup will be performed
- Temperature-based control will be disabled automatically

### 🔧 Service Issues

**Problem**: Service won't start
```bash
# Check service status and logs
sudo systemctl status ilo4-fan-control
sudo journalctl -u ilo4-fan-control -n 20

# Check script syntax
sudo bash -n /usr/local/bin/ilo4-fan-control.sh

# Test script manually
sudo /usr/local/bin/ilo4-fan-control.sh
```

**Problem**: Service starts but doesn't work
```bash
# Check configuration file
sudo cat /etc/ilo4-fan-control/ilo4-fan-control.conf

# Increase logging level temporarily
sudo sed -i 's/LOG_LEVEL="INFO"/LOG_LEVEL="DEBUG"/' /etc/ilo4-fan-control/ilo4-fan-control.conf
sudo systemctl restart ilo4-fan-control

# Check detailed logs
sudo tail -f /var/log/ilo4-fan-control.log
```

### 🆘 Emergency Procedures

**If fans get stuck at high speed:**
```bash
# Reset to safe defaults
sudo ilo4-fan-control-manual.sh --reset

# Or stop the service and manually set speeds
sudo systemctl stop ilo4-fan-control
sudo ilo4-fan-control-manual.sh --set-all 60
```

**If system overheats:**
```bash
# Emergency maximum cooling
sudo ilo4-fan-control-manual.sh --emergency

# Check current temperatures
sudo sensors
sudo ilo4-fan-control-manual.sh --status
```

## 🤝 Support and Contributing

### 📝 Getting Help

1. **Check logs**: Always check both systemd logs and script logs
2. **Test manually**: Use the manual control script to isolate issues
3. **Verify configuration**: Ensure all settings are correct
4. **Check connectivity**: Verify network and SSH access to iLO

### 🐛 Reporting Issues

When reporting issues, please include:
- Operating system and version
- HP server model and iLO version
- Complete error logs from both systemd and script logs
- Configuration file contents (remove passwords)
- Output from manual test commands

### 🔄 Version History

- **v2.0.0**: Complete rewrite with configurable temperature thresholds
- **v1.x**: Original hardcoded temperature system

For the latest updates and contributions, visit the project repository.

---

**⚠️ Important Notes:**
- This script stores iLO credentials in plain text - ensure proper file permissions
- Always test configuration changes in a safe environment first
- Keep backups of working configurations before making changes
- The system includes emergency protection, but manual monitoring is still recommended

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

# iLO4 Fan Control

## Installation
To install the iLO4 fan control system, run the following command:

```bash
sudo ./install.sh
```
Alternatively, you can use the following one-liner to install directly from the GitHub repository:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --install
```

## Update
To update the iLO4 fan control system to the latest version, use the `update` flag:

```bash
sudo ./install.sh update
```
Alternatively, you can use the following one-liner to update directly from the GitHub repository:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --update
```

## Configuration
Refer to the `ilo4-fan-control.conf` file for configuration options. Ensure the file is correctly set up before running the script.

## Logs
Logs are stored in `/var/log/ilo4-fan-control.log`. Check this file for detailed information about the script's execution.

## Troubleshooting
If you encounter issues, verify the following:
- Network connectivity to the iLO host.
- Correct credentials in the configuration file.
- Proper permissions for the log directory.

For further assistance, consult the detailed logs or contact support.

## Installation

To install the iLO4 fan control system interactively:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --install
```

This will guide you through configuration and install all required files and services.

## Update

To update the iLO4 fan control system non-interactively (using your existing config):

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)" -- --update
```

- The update command will **not prompt for any input** and will use values from `/etc/ilo4-fan-control/ilo4-fan-control.conf`.
- If any required config field is missing, the update will abort with an error.

## Troubleshooting

- If you see an error about `BASH_SOURCE` or unbound variables, ensure you are using the latest version of the script (as above).
- The script logs to `/var/log/ilo4-fan-control.log`.

## Service Management

After installation, you can manage the service with:

```bash
sudo systemctl start ilo4-fan-control
sudo systemctl stop ilo4-fan-control
sudo systemctl status ilo4-fan-control
sudo journalctl -u ilo4-fan-control -f
```

## Configuration

Edit your configuration at:

```
sudo nano /etc/ilo4-fan-control/ilo4-fan-control.conf
```

Then restart the service:

```
sudo systemctl restart ilo4-fan-control
```

---

For more details, see comments in the configuration file or the main script.