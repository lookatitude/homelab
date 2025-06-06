#!/bin/bash

# Supermicro IPMI Fan Control Installation Script for Proxmox/Debian
# This script downloads, configures, and installs the IPMI fan control service
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi/install.sh)"

set -euo pipefail

# Repository configuration
REPO_BASE_URL="https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ipmi"
SCRIPT_URL="$REPO_BASE_URL/supermicro-fan-control.sh"
SERVICE_URL="$REPO_BASE_URL/supermicro-fan-control.service"
MANUAL_SCRIPT_URL="$REPO_BASE_URL/fan-control-manual.sh"
THRESHOLD_SCRIPT_URL="$REPO_BASE_URL/set-thresholds.sh"

echo "=========================================="
echo "Supermicro IPMI Fan Control Installation"
echo "=========================================="
echo "This script will install and configure an IPMI fan control service"
echo "that manages server fan speeds based on temperature thresholds."
echo "Compatible with Supermicro X10-X13 series boards."
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "⚠ WARNING: Running as root detected!"
    echo "It's generally recommended to run this script as a regular user with sudo access."
    echo "Running as root means the script will have elevated privileges throughout execution."
    echo ""
    read -p "Are you sure you want to continue as root? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Continuing with root privileges..."
    SUDO_CMD=""
else
    # Check if sudo is available for non-root users
    if ! command -v sudo &> /dev/null; then
        echo "ERROR: sudo is not available. Please install sudo first or run as root."
        exit 1
    fi
    SUDO_CMD="sudo"
fi

# Function to prompt for input with default
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local is_password="${4:-false}"
    
    if [[ "$is_password" == "true" ]]; then
        echo -n "$prompt [$default]: "
        read -s user_input
        echo  # New line after password input
    else
        echo -n "$prompt [$default]: "
        read user_input
    fi
    
    if [[ -z "$user_input" ]]; then
        eval "$varname=\"$default\""
    else
        eval "$varname=\"$user_input\""
    fi
}

# Function to prompt yes/no with default
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    
    while true; do
        echo -n "$prompt (y/n) [$default]: "
        read user_input
        
        if [[ -z "$user_input" ]]; then
            user_input="$default"
        fi
        
        case "$user_input" in
            [Yy]|[Yy][Ee][Ss])
                eval "$varname=true"
                break
                ;;
            [Nn]|[Nn][Oo])
                eval "$varname=false"
                break
                ;;
            *)
                echo "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

echo "Configuration Setup:"
echo "Please provide the following information for your IPMI setup."
echo ""

# Collect IPMI connection details
prompt_with_default "IPMI IP address or hostname" "192.168.1.100" "IPMI_HOST"
prompt_with_default "IPMI username" "ADMIN" "IPMI_USER"
prompt_with_default "IPMI password" "ADMIN" "IPMI_PASS" "true"
echo ""

# Collect fan configuration
echo "Fan Control Configuration:"
echo "Available fan modes: STANDARD (0), FULL (1), OPTIMAL (2), PUE (4), HEAVY_IO (3)"
prompt_with_default "Initial fan mode (0-4)" "1" "FAN_MODE"
prompt_with_default "Monitoring interval (seconds)" "30" "INTERVAL"
echo ""

# Temperature thresholds
echo "Temperature Control Settings:"
prompt_with_default "CPU zone low temperature (°C)" "35" "CPU_TEMP_LOW"
prompt_with_default "CPU zone high temperature (°C)" "70" "CPU_TEMP_HIGH"
prompt_with_default "CPU zone min fan speed (0-100%)" "25" "CPU_MIN_FAN"
prompt_with_default "CPU zone max fan speed (0-100%)" "100" "CPU_MAX_FAN"
echo ""

prompt_with_default "Hard drive zone low temperature (°C)" "30" "HD_TEMP_LOW"
prompt_with_default "Hard drive zone high temperature (°C)" "45" "HD_TEMP_HIGH"
prompt_with_default "Hard drive zone min fan speed (0-100%)" "25" "HD_MIN_FAN"
prompt_with_default "Hard drive zone max fan speed (0-100%)" "80" "HD_MAX_FAN"
echo ""

# Temperature sources
echo "Temperature Monitoring Sources:"
prompt_yes_no "Enable thermal zone monitoring" "y" "ENABLE_THERMAL_ZONES"
prompt_yes_no "Enable sensors command monitoring" "y" "ENABLE_SENSORS"
prompt_yes_no "Enable IPMI sensor monitoring" "y" "ENABLE_IPMI_SENSORS"
prompt_yes_no "Enable hard drive temperature monitoring" "y" "ENABLE_HD_MONITORING"
echo ""

# Advanced settings
echo "Advanced Settings:"
echo "Temperature calculation methods: min, avg, max"
prompt_with_default "CPU temperature calculation method" "max" "CPU_TEMP_CALC"
prompt_with_default "HD temperature calculation method" "max" "HD_TEMP_CALC"
echo ""

# Sensor thresholds configuration
echo "Sensor Thresholds Configuration:"
echo "Setting sensor thresholds prevents IPMI from taking over fan control."
prompt_yes_no "Auto-configure sensor thresholds" "y" "AUTO_THRESHOLDS"

if [[ "$AUTO_THRESHOLDS" == "true" ]]; then
    prompt_with_default "Lower threshold values (comma-separated)" "0,100,200" "LOWER_THRESHOLDS"
    prompt_with_default "Upper threshold values (comma-separated)" "1600,1700,1800" "UPPER_THRESHOLDS"
fi
echo ""

# Service configuration
echo "Service Configuration:"
prompt_yes_no "Enable systemd service" "y" "ENABLE_SERVICE"
prompt_yes_no "Start service immediately after installation" "y" "START_SERVICE"
echo ""

echo "Configuration Summary:"
echo "  IPMI Host: $IPMI_HOST"
echo "  IPMI User: $IPMI_USER"
echo "  Fan Mode: $FAN_MODE"
echo "  Monitor Interval: ${INTERVAL}s"
echo "  CPU Temp Range: ${CPU_TEMP_LOW}°C - ${CPU_TEMP_HIGH}°C"
echo "  CPU Fan Speed: ${CPU_MIN_FAN}% - ${CPU_MAX_FAN}%"
echo "  HD Temp Range: ${HD_TEMP_LOW}°C - ${HD_TEMP_HIGH}°C"
echo "  HD Fan Speed: ${HD_MIN_FAN}% - ${HD_MAX_FAN}%"
echo "  Thermal Zones: $ENABLE_THERMAL_ZONES"
echo "  Sensors: $ENABLE_SENSORS"
echo "  IPMI Sensors: $ENABLE_IPMI_SENSORS"
echo "  HD Monitoring: $ENABLE_HD_MONITORING"
echo "  Auto Thresholds: $AUTO_THRESHOLDS"
echo "  Enable Service: $ENABLE_SERVICE"
echo ""

read -p "Continue with installation? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo "Step 1: Checking and installing dependencies..."

# Function to check if package is installed
is_package_installed() {
    dpkg -l "$1" &> /dev/null
}

# List of required packages
REQUIRED_PACKAGES=("ipmitool" "wget" "curl")
OPTIONAL_PACKAGES=("lm-sensors" "smartmontools")

# Check and install required packages
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_package_installed "$package"; then
        MISSING_PACKAGES+=("$package")
    fi
done

# Check optional packages based on configuration
if [[ "$ENABLE_SENSORS" == "true" ]]; then
    if ! is_package_installed "lm-sensors"; then
        MISSING_PACKAGES+=("lm-sensors")
    fi
fi

if [[ "$ENABLE_HD_MONITORING" == "true" ]]; then
    if ! is_package_installed "smartmontools"; then
        MISSING_PACKAGES+=("smartmontools")
    fi
fi

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    $SUDO_CMD apt update
    $SUDO_CMD apt install -y "${MISSING_PACKAGES[@]}"
else
    echo "All required packages are already installed."
fi

echo "Step 2: Creating directories..."
$SUDO_CMD mkdir -p /usr/local/bin
$SUDO_CMD mkdir -p /var/log
$SUDO_CMD mkdir -p /etc/supermicro-fan-control

echo "Step 3: Downloading scripts..."

# Download the main fan control script
echo "Downloading main fan control script..."
if ! wget -q "$SCRIPT_URL" -O /tmp/supermicro-fan-control.sh; then
    echo "ERROR: Failed to download main fan control script from repository"
    echo "URL: $SCRIPT_URL"
    exit 1
fi

# Download the manual control script
echo "Downloading manual fan control script..."
if ! wget -q "$MANUAL_SCRIPT_URL" -O /tmp/fan-control-manual.sh; then
    echo "ERROR: Failed to download manual control script from repository"
    echo "URL: $MANUAL_SCRIPT_URL"
    exit 1
fi

# Download the threshold setting script
echo "Downloading threshold setting script..."
if ! wget -q "$THRESHOLD_SCRIPT_URL" -O /tmp/set-thresholds.sh; then
    echo "ERROR: Failed to download threshold setting script from repository"
    echo "URL: $THRESHOLD_SCRIPT_URL"
    exit 1
fi

echo "Step 4: Configuring fan control script..."

# Create configuration replacements
sed -i "s|IPMI_HOST=\".*\"|IPMI_HOST=\"$IPMI_HOST\"|g" /tmp/supermicro-fan-control.sh
sed -i "s|IPMI_USER=\".*\"|IPMI_USER=\"$IPMI_USER\"|g" /tmp/supermicro-fan-control.sh
sed -i "s|IPMI_PASS=\".*\"|IPMI_PASS=\"$IPMI_PASS\"|g" /tmp/supermicro-fan-control.sh
sed -i "s|FAN_MODE=.*|FAN_MODE=$FAN_MODE|g" /tmp/supermicro-fan-control.sh
sed -i "s|INTERVAL=.*|INTERVAL=$INTERVAL|g" /tmp/supermicro-fan-control.sh
sed -i "s|CPU_TEMP_LOW=.*|CPU_TEMP_LOW=$CPU_TEMP_LOW|g" /tmp/supermicro-fan-control.sh
sed -i "s|CPU_TEMP_HIGH=.*|CPU_TEMP_HIGH=$CPU_TEMP_HIGH|g" /tmp/supermicro-fan-control.sh
sed -i "s|CPU_MIN_FAN=.*|CPU_MIN_FAN=$CPU_MIN_FAN|g" /tmp/supermicro-fan-control.sh
sed -i "s|CPU_MAX_FAN=.*|CPU_MAX_FAN=$CPU_MAX_FAN|g" /tmp/supermicro-fan-control.sh
sed -i "s|HD_TEMP_LOW=.*|HD_TEMP_LOW=$HD_TEMP_LOW|g" /tmp/supermicro-fan-control.sh
sed -i "s|HD_TEMP_HIGH=.*|HD_TEMP_HIGH=$HD_TEMP_HIGH|g" /tmp/supermicro-fan-control.sh
sed -i "s|HD_MIN_FAN=.*|HD_MIN_FAN=$HD_MIN_FAN|g" /tmp/supermicro-fan-control.sh
sed -i "s|HD_MAX_FAN=.*|HD_MAX_FAN=$HD_MAX_FAN|g" /tmp/supermicro-fan-control.sh
sed -i "s|ENABLE_THERMAL_ZONES=.*|ENABLE_THERMAL_ZONES=$ENABLE_THERMAL_ZONES|g" /tmp/supermicro-fan-control.sh
sed -i "s|ENABLE_SENSORS=.*|ENABLE_SENSORS=$ENABLE_SENSORS|g" /tmp/supermicro-fan-control.sh
sed -i "s|ENABLE_IPMI_SENSORS=.*|ENABLE_IPMI_SENSORS=$ENABLE_IPMI_SENSORS|g" /tmp/supermicro-fan-control.sh
sed -i "s|ENABLE_HD_MONITORING=.*|ENABLE_HD_MONITORING=$ENABLE_HD_MONITORING|g" /tmp/supermicro-fan-control.sh
sed -i "s|CPU_TEMP_CALC=\".*\"|CPU_TEMP_CALC=\"$CPU_TEMP_CALC\"|g" /tmp/supermicro-fan-control.sh
sed -i "s|HD_TEMP_CALC=\".*\"|HD_TEMP_CALC=\"$HD_TEMP_CALC\"|g" /tmp/supermicro-fan-control.sh

# Configure manual script
sed -i "s|IPMI_HOST=\".*\"|IPMI_HOST=\"$IPMI_HOST\"|g" /tmp/fan-control-manual.sh
sed -i "s|IPMI_USER=\".*\"|IPMI_USER=\"$IPMI_USER\"|g" /tmp/fan-control-manual.sh
sed -i "s|IPMI_PASS=\".*\"|IPMI_PASS=\"$IPMI_PASS\"|g" /tmp/fan-control-manual.sh

# Configure threshold script
sed -i "s|IPMI_HOST=\".*\"|IPMI_HOST=\"$IPMI_HOST\"|g" /tmp/set-thresholds.sh
sed -i "s|IPMI_USER=\".*\"|IPMI_USER=\"$IPMI_USER\"|g" /tmp/set-thresholds.sh
sed -i "s|IPMI_PASS=\".*\"|IPMI_PASS=\"$IPMI_PASS\"|g" /tmp/set-thresholds.sh

# Install the configured scripts
$SUDO_CMD mv /tmp/supermicro-fan-control.sh /usr/local/bin/supermicro-fan-control.sh
$SUDO_CMD mv /tmp/fan-control-manual.sh /usr/local/bin/fan-control-manual.sh
$SUDO_CMD mv /tmp/set-thresholds.sh /usr/local/bin/set-thresholds.sh

$SUDO_CMD chmod +x /usr/local/bin/supermicro-fan-control.sh
$SUDO_CMD chmod +x /usr/local/bin/fan-control-manual.sh
$SUDO_CMD chmod +x /usr/local/bin/set-thresholds.sh

echo "Step 5: Setting up sensor thresholds..."
if [[ "$AUTO_THRESHOLDS" == "true" ]]; then
    echo "Configuring sensor thresholds to prevent IPMI takeover..."
    # Convert comma-separated thresholds to space-separated
    LOWER_THRESH_ARGS=$(echo "$LOWER_THRESHOLDS" | sed 's/,/ /g')
    UPPER_THRESH_ARGS=$(echo "$UPPER_THRESHOLDS" | sed 's/,/ /g')
    
    echo "Setting thresholds with values: lower=($LOWER_THRESH_ARGS) upper=($UPPER_THRESH_ARGS)"
    if $SUDO_CMD /usr/local/bin/set-thresholds.sh --preset custom --lower $LOWER_THRESH_ARGS --upper $UPPER_THRESH_ARGS --yes; then
        echo "✓ Sensor thresholds configured successfully"
    else
        echo "⚠ Warning: Could not configure sensor thresholds automatically"
        echo "  You may need to run set-thresholds.sh manually after ensuring IPMI connectivity"
    fi
fi

if [[ "$ENABLE_SERVICE" == "true" ]]; then
    echo "Step 6: Downloading and installing systemd service..."
    # Download the service file from repository
    if ! wget -q "$SERVICE_URL" -O /tmp/supermicro-fan-control.service; then
        echo "ERROR: Failed to download service file from repository"
        echo "URL: $SERVICE_URL"
        exit 1
    fi

    # Install service file
    $SUDO_CMD mv /tmp/supermicro-fan-control.service /etc/systemd/system/supermicro-fan-control.service

    echo "Step 7: Enabling systemd service..."
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable supermicro-fan-control.service
fi

echo "Step 8: Testing the configuration..."
echo "Testing IPMI connection..."
if timeout 10 ipmitool -I lanplus -H "$IPMI_HOST" -U "$IPMI_USER" -P "$IPMI_PASS" chassis status &>/dev/null; then
    echo "✓ IPMI connection successful"
    
    echo "Running a quick test of the fan control script..."
    if $SUDO_CMD timeout 60 /usr/local/bin/supermicro-fan-control.sh --test &>/dev/null; then
        echo "✓ Script test completed successfully"
    else
        echo "⚠ Script test had issues, but installation is complete"
    fi
else
    echo "⚠ IPMI connection test failed. Please verify IPMI credentials and network connectivity."
    echo "  The service is installed but may not work until connection issues are resolved."
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Installed Components:"
echo "  Main script: /usr/local/bin/supermicro-fan-control.sh"
echo "  Manual control: /usr/local/bin/fan-control-manual.sh"
echo "  Threshold tool: /usr/local/bin/set-thresholds.sh"
if [[ "$ENABLE_SERVICE" == "true" ]]; then
    echo "  Service file: /etc/systemd/system/supermicro-fan-control.service"
fi
echo "  Log file: /var/log/supermicro-fan-control.log"
echo ""
echo "Configuration Applied:"
echo "  IPMI Host: $IPMI_HOST"
echo "  IPMI User: $IPMI_USER"
echo "  Fan Mode: $FAN_MODE"
echo "  Monitor Interval: ${INTERVAL}s"
echo "  CPU Temp Range: ${CPU_TEMP_LOW}°C - ${CPU_TEMP_HIGH}°C (${CPU_MIN_FAN}% - ${CPU_MAX_FAN}%)"
echo "  HD Temp Range: ${HD_TEMP_LOW}°C - ${HD_TEMP_HIGH}°C (${HD_MIN_FAN}% - ${HD_MAX_FAN}%)"
echo ""
echo "Available Commands:"
echo "  Main fan control:     /usr/local/bin/supermicro-fan-control.sh [options]"
echo "  Manual fan control:   /usr/local/bin/fan-control-manual.sh [options]"
echo "  Configure thresholds: /usr/local/bin/set-thresholds.sh [options]"
echo ""

if [[ "$ENABLE_SERVICE" == "true" ]]; then
    echo "Service Management Commands:"
    echo "  Start service:    ${SUDO_CMD} systemctl start supermicro-fan-control"
    echo "  Stop service:     ${SUDO_CMD} systemctl stop supermicro-fan-control"
    echo "  Check status:     ${SUDO_CMD} systemctl status supermicro-fan-control"
    echo "  View logs:        ${SUDO_CMD} journalctl -u supermicro-fan-control -f"
    echo "  View script logs: ${SUDO_CMD} tail -f /var/log/supermicro-fan-control.log"
    echo ""
    
    if [[ "$START_SERVICE" == "true" ]]; then
        echo "Starting the service now..."
        if $SUDO_CMD systemctl start supermicro-fan-control; then
            echo "✓ Service started successfully"
            $SUDO_CMD systemctl status supermicro-fan-control --no-pager
        else
            echo "⚠ Failed to start service. Check logs for details."
        fi
    else
        echo "The service is enabled and will start automatically on boot."
        echo "To start it now, run: ${SUDO_CMD} systemctl start supermicro-fan-control"
    fi
    echo ""
fi

echo "Usage Examples:"
echo "  Check status:         /usr/local/bin/supermicro-fan-control.sh --status"
echo "  Run once:             /usr/local/bin/supermicro-fan-control.sh --once"
echo "  Manual fan control:   /usr/local/bin/fan-control-manual.sh --interactive"
echo "  Set fan to 50%:       /usr/local/bin/fan-control-manual.sh --zone 0 --speed 50"
echo "  Reset thresholds:     /usr/local/bin/set-thresholds.sh --preset safe"
echo ""
echo "Configuration files can be found in: /etc/supermicro-fan-control/"
echo "To modify settings, edit the scripts in /usr/local/bin/ and restart the service."
echo ""
echo "For help and documentation, run any script with --help option."
