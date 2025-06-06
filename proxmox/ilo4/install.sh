#!/bin/bash

# iLO4 Fan Control Installation Script for Proxmox/Debian
# This script downloads, configures, and installs the iLO4 fan control service
# Usage: sh -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/master/proxmox/ilo4/install.sh)"

set -euo pipefail

# Repository configuration
REPO_BASE_URL="https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4"
SCRIPT_URL="$REPO_BASE_URL/ilo4-fan-control.sh"
SERVICE_URL="$REPO_BASE_URL/ilo4-fan-control.service"

echo "=========================================="
echo "iLO4 Fan Control Installation Script"
echo "=========================================="
echo "This script will install and configure an iLO4 fan control service"
echo "that manages server fan speeds based on temperature thresholds."
echo ""

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    echo "ERROR: This script should not be run as root directly."
    echo "Please run as a regular user with sudo access."
    exit 1
fi

# Check if sudo is available
if ! command -v sudo &> /dev/null; then
    echo "ERROR: sudo is not available. Please install sudo first."
    exit 1
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
echo "Please provide the following information for your iLO4 setup."
echo ""

# Collect iLO connection details
prompt_with_default "iLO4 IP address or hostname" "192.168.1.100" "ILO_HOST"
prompt_with_default "iLO4 username" "Administrator" "ILO_USER"
prompt_with_default "iLO4 password" "password" "ILO_PASS" "true"
echo ""

# Collect fan configuration
echo "Fan Configuration:"
prompt_with_default "Number of fans" "6" "FAN_COUNT"
prompt_with_default "Global minimum fan speed (0-255)" "60" "GLOBAL_MIN_SPEED"
prompt_with_default "PID minimum low value" "1600" "PID_MIN_LOW"
echo ""

# Collect disabled sensors (comma-separated)
echo "Disabled sensors (comma-separated hex values, e.g., 07FB00,35,38):"
prompt_with_default "Sensors to disable" "07FB00,35,38" "DISABLED_SENSORS_INPUT"
# Convert comma-separated to array format
DISABLED_SENSORS="($(echo "$DISABLED_SENSORS_INPUT" | sed 's/,/ /g'))"
echo ""

# Dynamic control settings
echo "Dynamic Fan Control Settings:"
prompt_yes_no "Enable dynamic temperature-based fan control" "n" "ENABLE_DYNAMIC_CONTROL"

if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
    prompt_with_default "Temperature monitoring interval (seconds)" "30" "MONITORING_INTERVAL"
    
    echo "CPU1 fan assignments (space-separated, e.g., 3 4 5):"
    prompt_with_default "CPU1 fans" "3 4 5" "CPU1_FANS_INPUT"
    CPU1_FANS="($(echo "$CPU1_FANS_INPUT"))"
    
    echo "CPU2 fan assignments (space-separated, e.g., 0 1 2):"
    prompt_with_default "CPU2 fans" "0 1 2" "CPU2_FANS_INPUT"
    CPU2_FANS="($(echo "$CPU2_FANS_INPUT"))"
else
    MONITORING_INTERVAL="30"
    CPU1_FANS="(3 4 5)"
    CPU2_FANS="(0 1 2)"
fi

echo ""
echo "Configuration Summary:"
echo "  iLO Host: $ILO_HOST"
echo "  iLO User: $ILO_USER"
echo "  Fan Count: $FAN_COUNT"
echo "  Min Speed: $GLOBAL_MIN_SPEED"
echo "  Dynamic Control: $ENABLE_DYNAMIC_CONTROL"
if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
    echo "  Monitor Interval: ${MONITORING_INTERVAL}s"
fi
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
REQUIRED_PACKAGES=("sshpass" "openssh-client" "wget" "curl")
OPTIONAL_PACKAGES=("lm-sensors" "jq")  # For temperature monitoring if running locally

# Check and install required packages
MISSING_PACKAGES=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! is_package_installed "$package"; then
        MISSING_PACKAGES+=("$package")
    fi
done

# Check optional packages if dynamic control is enabled
if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
    for package in "${OPTIONAL_PACKAGES[@]}"; do
        if ! is_package_installed "$package"; then
            MISSING_PACKAGES+=("$package")
        fi
    done
fi

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
    echo "Installing missing packages: ${MISSING_PACKAGES[*]}"
    sudo apt update
    sudo apt install -y "${MISSING_PACKAGES[@]}"
else
    echo "All required packages are already installed."
fi

echo "Step 2: Creating directories..."
sudo mkdir -p /usr/local/bin
sudo mkdir -p /var/log

echo "Step 3: Downloading fan control script..."
# Download the script from repository
if ! wget -q "$SCRIPT_URL" -O /tmp/ilo4-fan-control.sh; then
    echo "ERROR: Failed to download fan control script from repository"
    echo "URL: $SCRIPT_URL"
    exit 1
fi

echo "Step 4: Configuring fan control script..."
# Replace configuration placeholders in the downloaded script
sed -i "s|ILO_HOST=\".*\"|ILO_HOST=\"$ILO_HOST\"|g" /tmp/ilo4-fan-control.sh
sed -i "s|ILO_USER=\".*\"|ILO_USER=\"$ILO_USER\"|g" /tmp/ilo4-fan-control.sh
sed -i "s|ILO_PASS=\".*\"|ILO_PASS=\"$ILO_PASS\"|g" /tmp/ilo4-fan-control.sh
sed -i "s|FAN_COUNT=.*|FAN_COUNT=$FAN_COUNT|g" /tmp/ilo4-fan-control.sh
sed -i "s|GLOBAL_MIN_SPEED=.*|GLOBAL_MIN_SPEED=$GLOBAL_MIN_SPEED|g" /tmp/ilo4-fan-control.sh
sed -i "s|PID_MIN_LOW=.*|PID_MIN_LOW=$PID_MIN_LOW|g" /tmp/ilo4-fan-control.sh
sed -i "s|DISABLED_SENSORS=.*|DISABLED_SENSORS=$DISABLED_SENSORS|g" /tmp/ilo4-fan-control.sh
sed -i "s|ENABLE_DYNAMIC_CONTROL=.*|ENABLE_DYNAMIC_CONTROL=$ENABLE_DYNAMIC_CONTROL|g" /tmp/ilo4-fan-control.sh
sed -i "s|MONITORING_INTERVAL=.*|MONITORING_INTERVAL=$MONITORING_INTERVAL|g" /tmp/ilo4-fan-control.sh
sed -i "s|CPU1_FANS=.*|CPU1_FANS=$CPU1_FANS|g" /tmp/ilo4-fan-control.sh
sed -i "s|CPU2_FANS=.*|CPU2_FANS=$CPU2_FANS|g" /tmp/ilo4-fan-control.sh

# Install the configured script
sudo mv /tmp/ilo4-fan-control.sh /usr/local/bin/ilo4-fan-control.sh
sudo chmod +x /usr/local/bin/ilo4-fan-control.sh

echo "Step 5: Downloading and installing systemd service..."
# Download the service file from repository
if ! wget -q "$SERVICE_URL" -O /tmp/ilo4-fan-control.service; then
    echo "ERROR: Failed to download service file from repository"
    echo "URL: $SERVICE_URL"
    exit 1
fi

# Install service file
sudo mv /tmp/ilo4-fan-control.service /etc/systemd/system/ilo4-fan-control.service
# Install service file
sudo mv /tmp/ilo4-fan-control.service /etc/systemd/system/ilo4-fan-control.service

echo "Step 6: Enabling and configuring systemd service..."
sudo systemctl daemon-reload
sudo systemctl enable ilo4-fan-control.service

echo "Step 7: Testing the configuration..."
echo "Testing SSH connection to iLO..."
if timeout 10 sshpass -p "$ILO_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$ILO_USER@$ILO_HOST" "version" &>/dev/null; then
    echo "✓ SSH connection to iLO successful"
    
    echo "Running a quick test of the fan control script..."
    if sudo timeout 60 /usr/local/bin/ilo4-fan-control.sh &>/dev/null; then
        echo "✓ Script test completed successfully"
    else
        echo "⚠ Script test had issues, but service is installed"
    fi
else
    echo "⚠ SSH connection test failed. Please verify iLO credentials and network connectivity."
    echo "  The service is installed but may not work until connection issues are resolved."
fi

echo ""
echo "=========================================="
echo "Installation Complete!"
echo "=========================================="
echo ""
echo "Service Status:"
echo "  Service file: /etc/systemd/system/ilo4-fan-control.service"
echo "  Script location: /usr/local/bin/ilo4-fan-control.sh"
echo "  Log file: /var/log/ilo4-fan-control.log"
echo ""
echo "Configuration Applied:"
echo "  iLO Host: $ILO_HOST"
echo "  iLO User: $ILO_USER"
echo "  Fan Count: $FAN_COUNT"
echo "  Min Speed: $GLOBAL_MIN_SPEED"
echo "  Dynamic Control: $ENABLE_DYNAMIC_CONTROL"
echo ""
echo "Service Management Commands:"
echo "  Start service:    sudo systemctl start ilo4-fan-control"
echo "  Stop service:     sudo systemctl stop ilo4-fan-control"
echo "  Check status:     sudo systemctl status ilo4-fan-control"
echo "  View logs:        sudo journalctl -u ilo4-fan-control -f"
echo "  View script logs: sudo tail -f /var/log/ilo4-fan-control.log"
echo ""
echo "The service is enabled and will start automatically on boot."
echo "To start it now, run: sudo systemctl start ilo4-fan-control"
echo ""
echo "If you need to modify the configuration later, edit:"
echo "  /usr/local/bin/ilo4-fan-control.sh"
echo "Then restart the service with: sudo systemctl restart ilo4-fan-control"
