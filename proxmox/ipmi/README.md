# Supermicro IPMI Fan Control

A comprehensive bash-based IPMI fan control system for Supermicro X10-X13 series motherboards, inspired by the excellent [smfc](https://github.com/petersulyok/smfc) project. This implementation provides dynamic temperature-based fan control while avoiding Python dependencies.

## Features

- **Dynamic Temperature Control**: Automatic fan speed adjustment based on CPU and HDD temperatures
- **IPMI Zone Management**: Separate control for CPU zone (0) and peripheral/HD zone (1)
- **Sensor Threshold Management**: Prevents IPMI from taking over fan control by setting safe thresholds
- **Multiple Temperature Sources**: Supports thermal zones, sensors command, IPMI sensors, and HDD monitoring
- **Flexible Fan Curves**: Configurable temperature-to-fan-speed mapping with multiple calculation methods
- **Daemon Mode**: Runs as a systemd service for continuous monitoring
- **Manual Control**: Utilities for manual fan control and threshold management
- **Auto-detection**: Automatically detects available fans using IPMI sensor data
- **Safety Features**: Automatic reset to safe fan levels on shutdown

## Compatibility

- **Motherboards**: Supermicro X10, X11, X12, X13 series
- **Operating Systems**: Linux (Debian/Ubuntu/Proxmox recommended)
- **Requirements**: ipmitool, bash, bc, smartmontools, lm-sensors

## Quick Start

### One-Line Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/install.sh)"
```

This will:
- Download all required scripts from GitHub
- Prompt for your IPMI configuration
- Install dependencies automatically
- Configure systemd service
- Test the connection and start monitoring

### Manual Installation Steps

1. **Download and Install**:
   ```bash
   wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/install.sh
   chmod +x install.sh
   sudo ./install.sh
   ```

2. **Test the Installation**:
   ```bash
   sudo supermicro-fan-control.sh --status
   ```

3. **Check Service Status**:
   ```bash
   sudo systemctl status supermicro-fan-control
   ```

## Installation

### Automatic Installation (Recommended)

The installation script provides an interactive setup process:

```bash
# Download and run the installer
bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/ipmi-install.sh)"
```

The installer will prompt you for:
- IPMI connection details (IP, username, password)
- Fan control preferences
- Temperature monitoring configuration
- Service installation options

### Manual Installation

If you prefer to install manually or need custom setup:

1. **Install Dependencies**:
   ```bash
   sudo apt update
   sudo apt install ipmitool bc smartmontools lm-sensors
   ```

2. **Download Scripts**:
   ```bash
   wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/supermicro-fan-control.sh
   wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/supermicro-fan-control.service
   wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/fan-control-manual.sh
   wget https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/set-thresholds.sh
   ```

3. **Install and Configure**:
   ```bash
   sudo mkdir -p /usr/local/bin
   sudo cp *.sh /usr/local/bin/
   sudo cp *.service /etc/systemd/system/
   sudo chmod +x /usr/local/bin/*.sh
   # Edit configuration in scripts as needed
   sudo systemctl enable supermicro-fan-control.service
   ```

## Configuration

The main configuration is embedded in the script header. Key parameters:

### IPMI Settings
```bash
FAN_MODE="FULL"                    # IPMI fan mode (STANDARD/FULL/OPTIMAL/PUE/HEAVY_IO)
FAN_MODE_DELAY=10                  # Delay after mode change (seconds)
FAN_LEVEL_DELAY=2                  # Delay after level change (seconds)
```

### CPU Zone Configuration
```bash
CPU_MIN_TEMP=30.0                  # Minimum CPU temperature (°C)
CPU_MAX_TEMP=70.0                  # Maximum CPU temperature (°C)
CPU_MIN_FAN_LEVEL=35               # Minimum fan level (%)
CPU_MAX_FAN_LEVEL=100              # Maximum fan level (%)
CPU_TEMP_CALC="avg"                # Temperature calculation: min/avg/max
```

### HDD Zone Configuration
```bash
HD_MIN_TEMP=25.0                   # Minimum HDD temperature (°C)
HD_MAX_TEMP=45.0                   # Maximum HDD temperature (°C)
HD_MIN_FAN_LEVEL=25                # Minimum fan level (%)
HD_MAX_FAN_LEVEL=80                # Maximum fan level (%)
HD_TEMP_CALC="max"                 # Temperature calculation: min/avg/max
```

### Sensor Thresholds
```bash
THRESHOLD_LOWER=(0 100 200)        # Lower thresholds: non-recoverable, critical, non-critical
THRESHOLD_UPPER=(1600 1700 1800)   # Upper thresholds: non-critical, critical, non-recoverable
```

## Usage

### Main Script Commands

```bash
# Run as daemon (continuous monitoring)
sudo /opt/supermicro-fan-control/supermicro-fan-control.sh --daemon

# Initialize system only
sudo /opt/supermicro-fan-control/supermicro-fan-control.sh --init-only

# Set sensor thresholds only
sudo /opt/supermicro-fan-control/supermicro-fan-control.sh --set-thresholds

# Show current status
sudo supermicro-fan-control.sh --status

# One-shot execution (init + single control cycle)
sudo supermicro-fan-control.sh --once

# Test mode (no actual changes)
sudo supermicro-fan-control.sh --test

# Daemon mode (continuous monitoring)
sudo supermicro-fan-control.sh --daemon
```

### Manual Fan Control

Use the manual control utility for immediate fan adjustments:

```bash
# Interactive mode
sudo fan-control-manual.sh --interactive

# Show current status  
sudo fan-control-manual.sh --status

# Set fan mode
sudo fan-control-manual.sh --mode FULL

# Set specific zone level
sudo fan-control-manual.sh --zone 0 --speed 50  # CPU zone to 50%
sudo fan-control-manual.sh --zone 1 --speed 30  # HD zone to 30%

# Reset to safe levels
sudo fan-control-manual.sh --reset
```

### Threshold Management

Use the threshold utility to configure sensor thresholds:

```bash
# Interactive configuration
sudo set-thresholds.sh --interactive

# Show current thresholds
sudo set-thresholds.sh --show

# Apply preset configurations
sudo set-thresholds.sh --preset safe        # Conservative thresholds
sudo set-thresholds.sh --preset noctua      # For Noctua fans
sudo set-thresholds.sh --preset performance # Aggressive thresholds

# Set custom thresholds for all fans
sudo set-thresholds.sh --preset custom --lower 0 100 200 --upper 1600 1700 1800

# Detect available fans
sudo set-thresholds.sh --detect
```

### Service Management

```bash
# Start/stop service
sudo systemctl start supermicro-fan-control.service
sudo systemctl stop supermicro-fan-control.service

# Enable/disable automatic startup
sudo systemctl enable supermicro-fan-control.service
sudo systemctl disable supermicro-fan-control.service

# Check service status
sudo systemctl status supermicro-fan-control.service

# View logs
sudo journalctl -u supermicro-fan-control.service -f
```

## IPMI Zones and Fan Layout

### Typical Supermicro Fan Configuration

| Zone | Name | Fans | Purpose |
|------|------|------|---------|
| 0 | CPU/System Zone | FAN1, FAN2, FAN3, FAN4 | CPU and system cooling |
| 1 | Peripheral/HD Zone | FANA, FANB, FANC, FAND | Hard drive and peripheral cooling |

### Fan Modes

| Mode | Value | Description |
|------|-------|-------------|
| STANDARD | 0 | Default IPMI control |
| FULL | 1 | Manual control (recommended) |
| OPTIMAL | 2 | IPMI optimal with override |
| PUE | 3 | Power usage effectiveness mode |
| HEAVY_IO | 4 | High I/O workload mode |

## Temperature Sources

The system automatically detects and uses available temperature sources:

1. **CPU Temperature**:
   - `/sys/class/thermal/thermal_zone*/temp` (preferred)
   - `sensors` command output
   - IPMI temperature sensors
   - Fallback: 40°C

2. **HDD Temperature**:
   - `smartctl` SMART data (primary method)
   - IPMI HDD temperature sensors (if available)
   - Fallback: 30°C

## Sensor Thresholds

IPMI uses sensor thresholds to determine when to take over fan control. Setting appropriate thresholds is crucial:

### Threshold Types (X10/X11/X12 boards)
- **Lower Non-Recoverable**: Fan completely stopped
- **Lower Critical**: Fan critically slow  
- **Lower Non-Critical**: Fan slower than normal
- **Upper Non-Critical**: Fan faster than normal
- **Upper Critical**: Fan critically fast
- **Upper Non-Recoverable**: Fan dangerously fast

### Threshold Types (X13 boards)
- **Lower Critical**: Minimum acceptable RPM

### Example for Noctua NF-F12 PWM (300-1500 RPM)
```bash
Lower thresholds:  0, 100, 200 RPM
Upper thresholds:  1600, 1700, 1800 RPM
```

## Troubleshooting

### Common Issues

1. **"IPMI command failed"**:
   - Check if IPMI is enabled in BIOS
   - Ensure `ipmi_si` and `ipmi_devintf` modules are loaded
   - Verify you're running as root or with sudo

2. **"No fans detected"**:
   - Run `ipmitool sdr list` to check available sensors
   - Some fans may not be connected or recognized
   - Try resetting BMC: `ipmitool mc reset cold`

3. **Fans spinning at 100%**:
   - IPMI has likely taken over due to threshold violation
   - Check logs: `journalctl -u supermicro-fan-control.service`
   - Verify sensor thresholds: `./set-thresholds.sh show`
   - Adjust thresholds if necessary

4. **Temperature reading issues**:
   - Install `lm-sensors`: `sudo apt install lm-sensors && sudo sensors-detect`
   - Install `smartmontools`: `sudo apt install smartmontools`
   - Check sensor availability: `sensors` and `smartctl -A /dev/sda`
   - Note: `hddtemp` is deprecated; use `smartctl` for HDD temperatures

### Debugging Commands

```bash
# Check IPMI functionality
ipmitool sdr list
ipmitool sensor
ipmitool sel list

# Check temperature sources
cat /sys/class/thermal/thermal_zone*/temp
sensors
smartctl -A /dev/sda

# Test fan control manually
ipmitool raw 0x30 0x45 0x01 0x01  # Set FULL mode
ipmitool raw 0x30 0x70 0x66 0x01 0x00 0x32  # Set CPU zone to 50%

# Check kernel modules
lsmod | grep ipmi
```

### Logging

Logs are written to:
- **System journal**: `journalctl -u supermicro-fan-control.service`
- **Log file**: `/var/log/supermicro-fan-control.log`

Log levels:
- **INFO**: Normal operation events
- **WARN**: Non-critical issues
- **ERROR**: Critical errors
- **DEBUG**: Detailed diagnostic information

## Advanced Configuration

### Custom Temperature Curves

Modify the `calculate_fan_level` function to implement custom fan curves:

```bash
# Linear curve (default)
fan_level = min_level + (temp - min_temp) / (max_temp - min_temp) * (max_level - min_level)

# Aggressive curve (faster ramp-up)
# Square the temperature ratio for more aggressive response
```

### Multiple Temperature Sources

Configure additional temperature inputs by modifying the temperature reading functions:

```bash
# Add custom temperature source
get_custom_temperature() {
    # Your custom temperature logic here
    echo "45"
}
```

### Remote IPMI

For remote IPMI management, configure the IPMI connection parameters:

```bash
IPMI_USER="admin"
IPMI_PASS="password"
IPMI_HOST="192.168.1.100"
```

## Safety Considerations

1. **Always test thoroughly** before deploying in production
2. **Monitor logs** for the first few hours after installation
3. **Have console access** available in case of issues
4. **Understand your hardware** - fan specifications and thermal limits
5. **Set conservative thresholds** initially, then optimize
6. **Regular monitoring** of temperatures and fan speeds

## Contributing

Contributions are welcome! Please:

1. Test thoroughly on your hardware
2. Document any hardware-specific changes
3. Follow the existing code style
4. Update documentation as needed

## License

This project is inspired by and builds upon the excellent work of [petersulyok/smfc](https://github.com/petersulyok/smfc). Please refer to the original project for licensing terms.

## Acknowledgments

- **Peter Sulyok** for the original [smfc](https://github.com/petersulyok/smfc) project
- **Supermicro community** for IPMI documentation and reverse engineering
- **ServeTheHome forums** for fan control techniques and troubleshooting

## Support

For issues and questions:

1. Check the troubleshooting section above
2. Review logs for error messages
3. Test with manual commands to isolate issues
4. Consult the original [smfc documentation](https://github.com/petersulyok/smfc) for additional insights

---

**Disclaimer**: This software controls critical system components. Use at your own risk. Always ensure you have alternate cooling and console access before deployment.
