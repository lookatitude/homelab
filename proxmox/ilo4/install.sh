#!/bin/bash

# iLO4 Fan Control Installation Script for Proxmox/Debian
# This script downloads, configures, and installs the iLO4 fan control service
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)"

set -euo pipefail

# Script version and info
SCRIPT_VERSION="2.0.0"
INSTALLER_NAME="iLO4 Fan Control Installer"

# Repository configuration
REPO_BASE_URL="https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4"
SCRIPT_URL="$REPO_BASE_URL/ilo4-fan-control.sh"
SERVICE_URL="$REPO_BASE_URL/ilo4-fan-control.service"
CONFIG_URL="$REPO_BASE_URL/ilo4-fan-control.conf"
MANUAL_SCRIPT_URL="$REPO_BASE_URL/ilo4-fan-control-manual.sh"

# Installation paths
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/ilo4-fan-control"
SERVICE_DIR="/etc/systemd/system"
LOG_DIR="/var/log"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to show header
show_header() {
    print_color "$CYAN" "=========================================="
    print_color "$CYAN" "$INSTALLER_NAME v$SCRIPT_VERSION"
    print_color "$CYAN" "=========================================="
    print_color "$BLUE" "This script will install and configure an iLO4 fan control service"
    print_color "$BLUE" "that manages server fan speeds based on temperature thresholds."
    echo ""
}

# Function to detect OS and version
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        VER=$VERSION_ID
        print_color "$GREEN" "Detected OS: $OS $VER"
        
        # Check if this is a supported OS
        case "$ID" in
            debian|ubuntu|proxmox)
                print_color "$GREEN" "✓ Supported OS detected"
                ;;
            *)
                print_color "$YELLOW" "⚠ Warning: OS not explicitly tested, but should work"
                ;;
        esac
    else
        print_color "$YELLOW" "⚠ Warning: Cannot detect OS version"
    fi
    echo ""
}

# Function to check prerequisites
check_prerequisites() {
    print_color "$BLUE" "Checking prerequisites..."
    
    local missing_commands=()
    local required_commands=("wget" "curl" "systemctl" "ssh")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        print_color "$RED" "✗ Missing required commands: ${missing_commands[*]}"
        print_color "$YELLOW" "Please install these packages first and re-run the installer."
        exit 1
    fi
    
    # Check if systemd is running
    if ! systemctl is-system-running &>/dev/null; then
        print_color "$YELLOW" "⚠ Warning: systemd may not be running properly"
    fi
    
    print_color "$GREEN" "✓ Prerequisites check passed"
    echo ""
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    print_color "$YELLOW" "⚠ WARNING: Running as root detected!"
    print_color "$YELLOW" "It's generally recommended to run this script as a regular user with sudo access."
    print_color "$YELLOW" "Running as root means the script will have elevated privileges throughout execution."
    echo ""
    read -p "Are you sure you want to continue as root? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$RED" "Installation cancelled."
        exit 0
    fi
    print_color "$YELLOW" "Continuing with root privileges..."
    SUDO_CMD=""
else
    # Check if sudo is available for non-root users
    if ! command -v sudo &> /dev/null; then
        print_color "$RED" "ERROR: sudo is not available. Please install sudo first or run as root."
        exit 1
    fi
    SUDO_CMD="sudo"
fi

echo ""

# Function to prompt for input with default and validation
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local varname="$3"
    local is_password="${4:-false}"
    local validation_pattern="${5:-.*}"
    local validation_message="${6:-Invalid input}"
    
    while true; do
        if [[ "$is_password" == "true" ]]; then
            echo -n "$prompt [$default]: "
            read -s user_input
            echo  # New line after password input
        else
            echo -n "$prompt [$default]: "
            read user_input
        fi
        
        if [[ -z "$user_input" ]]; then
            user_input="$default"
        fi
        
        # Validate input
        if [[ "$user_input" =~ $validation_pattern ]]; then
            eval "$varname=\"$user_input\""
            break
        else
            print_color "$RED" "$validation_message"
        fi
    done
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
                print_color "$RED" "Please answer yes (y) or no (n)."
                ;;
        esac
    done
}

# Function to load existing configuration
load_existing_config() {
    local config_file="$CONFIG_DIR/ilo4-fan-control.conf"
    
    if [[ -f "$config_file" ]]; then
        print_color "$GREEN" "Found existing configuration file: $config_file"
        print_color "$BLUE" "Loading current settings as defaults..."
        
        # Source the config file safely to load current values
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            
            # Clean up the value (remove quotes and whitespace)
            value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//;s/^"//;s/"$//')
            
            case "$key" in
                ILO_HOST) DEFAULT_ILO_HOST="$value" ;;
                ILO_USER) DEFAULT_ILO_USER="$value" ;;
                ILO_PASS) DEFAULT_ILO_PASS="$value" ;;
                FAN_COUNT) DEFAULT_FAN_COUNT="$value" ;;
                GLOBAL_MIN_SPEED) DEFAULT_GLOBAL_MIN_SPEED="$value" ;;
                PID_MIN_LOW) DEFAULT_PID_MIN_LOW="$value" ;;
                ENABLE_DYNAMIC_CONTROL) DEFAULT_ENABLE_DYNAMIC_CONTROL="$value" ;;
                MONITORING_INTERVAL) DEFAULT_MONITORING_INTERVAL="$value" ;;
                MAX_TEMP_CPU) DEFAULT_MAX_TEMP_CPU="$value" ;;
                LOG_LEVEL) DEFAULT_LOG_LEVEL="$value" ;;
                CONNECTION_TIMEOUT) DEFAULT_CONNECTION_TIMEOUT="$value" ;;
                COMMAND_RETRIES) DEFAULT_COMMAND_RETRIES="$value" ;;
                TEMP_THRESHOLD_90) DEFAULT_TEMP_THRESHOLD_90="$value" ;;
                TEMP_THRESHOLD_80) DEFAULT_TEMP_THRESHOLD_80="$value" ;;
                TEMP_THRESHOLD_70) DEFAULT_TEMP_THRESHOLD_70="$value" ;;
                TEMP_THRESHOLD_60) DEFAULT_TEMP_THRESHOLD_60="$value" ;;
                TEMP_THRESHOLD_50) DEFAULT_TEMP_THRESHOLD_50="$value" ;;
                TEMP_THRESHOLD_DEFAULT) DEFAULT_TEMP_THRESHOLD_DEFAULT="$value" ;;
            esac
        done < "$config_file"
        
        # Load array values
        if grep -q "DISABLED_SENSORS=" "$config_file"; then
            local sensors_line=$(grep "DISABLED_SENSORS=" "$config_file" | head -1)
            DEFAULT_DISABLED_SENSORS_INPUT=$(echo "$sensors_line" | sed 's/DISABLED_SENSORS=(\(.*\))/\1/' | tr ' ' ',')
        fi
        
        if grep -q "CPU1_FANS=" "$config_file"; then
            local cpu1_line=$(grep "CPU1_FANS=" "$config_file" | head -1)
            DEFAULT_CPU1_FANS_INPUT=$(echo "$cpu1_line" | sed 's/CPU1_FANS=(\(.*\))/\1/')
        fi
        
        if grep -q "CPU2_FANS=" "$config_file"; then
            local cpu2_line=$(grep "CPU2_FANS=" "$config_file" | head -1)
            DEFAULT_CPU2_FANS_INPUT=$(echo "$cpu2_line" | sed 's/CPU2_FANS=(\(.*\))/\1/')
        fi
        
        echo ""
        return 0
    else
        print_color "$YELLOW" "No existing configuration found. Using system defaults."
        echo ""
        return 1
    fi
}

# Function to set default values
set_default_values() {
    # Set defaults (will be overridden by existing config if found)
    DEFAULT_ILO_HOST="${DEFAULT_ILO_HOST:-192.168.1.100}"
    DEFAULT_ILO_USER="${DEFAULT_ILO_USER:-Administrator}"
    DEFAULT_ILO_PASS="${DEFAULT_ILO_PASS:-password}"
    DEFAULT_FAN_COUNT="${DEFAULT_FAN_COUNT:-6}"
    DEFAULT_GLOBAL_MIN_SPEED="${DEFAULT_GLOBAL_MIN_SPEED:-60}"
    DEFAULT_PID_MIN_LOW="${DEFAULT_PID_MIN_LOW:-1600}"
    DEFAULT_DISABLED_SENSORS_INPUT="${DEFAULT_DISABLED_SENSORS_INPUT:-07FB00,35,38}"
    DEFAULT_ENABLE_DYNAMIC_CONTROL="${DEFAULT_ENABLE_DYNAMIC_CONTROL:-true}"
    DEFAULT_MONITORING_INTERVAL="${DEFAULT_MONITORING_INTERVAL:-30}"
    DEFAULT_CPU1_FANS_INPUT="${DEFAULT_CPU1_FANS_INPUT:-3 4 5}"
    DEFAULT_CPU2_FANS_INPUT="${DEFAULT_CPU2_FANS_INPUT:-0 1 2}"
    DEFAULT_MAX_TEMP_CPU="${DEFAULT_MAX_TEMP_CPU:-80}"
    DEFAULT_LOG_LEVEL="${DEFAULT_LOG_LEVEL:-INFO}"
    DEFAULT_CONNECTION_TIMEOUT="${DEFAULT_CONNECTION_TIMEOUT:-30}"
    DEFAULT_COMMAND_RETRIES="${DEFAULT_COMMAND_RETRIES:-3}"
    DEFAULT_TEMP_THRESHOLD_90="${DEFAULT_TEMP_THRESHOLD_90:-255}"
    DEFAULT_TEMP_THRESHOLD_80="${DEFAULT_TEMP_THRESHOLD_80:-200}"
    DEFAULT_TEMP_THRESHOLD_70="${DEFAULT_TEMP_THRESHOLD_70:-150}"
    DEFAULT_TEMP_THRESHOLD_60="${DEFAULT_TEMP_THRESHOLD_60:-100}"
    DEFAULT_TEMP_THRESHOLD_50="${DEFAULT_TEMP_THRESHOLD_50:-75}"
    DEFAULT_TEMP_THRESHOLD_DEFAULT="${DEFAULT_TEMP_THRESHOLD_DEFAULT:-50}"
}

# Function to collect configuration
collect_configuration() {
    print_color "$BLUE" "Configuration Setup:"
    print_color "$BLUE" "Please provide the following information for your iLO4 setup."
    echo ""

    # Load existing configuration if available
    load_existing_config
    set_default_values

    # iLO connection details
    print_color "$CYAN" "=== iLO4 Connection Settings ==="
    prompt_with_default "iLO4 IP address or hostname" "$DEFAULT_ILO_HOST" "ILO_HOST" false "^[a-zA-Z0-9.-]+$" "Please enter a valid IP address or hostname"
    prompt_with_default "iLO4 username" "$DEFAULT_ILO_USER" "ILO_USER" false "^[a-zA-Z0-9._-]+$" "Please enter a valid username"
    prompt_with_default "iLO4 password" "$DEFAULT_ILO_PASS" "ILO_PASS" "true"
    echo ""

    # Fan configuration
    print_color "$CYAN" "=== Fan Configuration ==="
    prompt_with_default "Number of fans" "$DEFAULT_FAN_COUNT" "FAN_COUNT" false "^[0-9]+$" "Please enter a number"
    prompt_with_default "Global minimum fan speed (0-255)" "$DEFAULT_GLOBAL_MIN_SPEED" "GLOBAL_MIN_SPEED" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
    prompt_with_default "PID minimum low value" "$DEFAULT_PID_MIN_LOW" "PID_MIN_LOW" false "^[0-9]+$" "Please enter a number"
    
    # Disabled sensors
    echo "Disabled sensors (comma-separated hex values, e.g., 07FB00,35,38):"
    prompt_with_default "Sensors to disable" "$DEFAULT_DISABLED_SENSORS_INPUT" "DISABLED_SENSORS_INPUT"
    echo ""

    # Temperature thresholds
    print_color "$CYAN" "=== Temperature Thresholds ==="
    prompt_yes_no "Use current/default temperature thresholds" "y" "USE_DEFAULT_THRESHOLDS"
    
    if [[ "$USE_DEFAULT_THRESHOLDS" == "false" ]]; then
        prompt_with_default "90°C threshold fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_90" "TEMP_THRESHOLD_90" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
        prompt_with_default "80°C threshold fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_80" "TEMP_THRESHOLD_80" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
        prompt_with_default "70°C threshold fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_70" "TEMP_THRESHOLD_70" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
        prompt_with_default "60°C threshold fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_60" "TEMP_THRESHOLD_60" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
        prompt_with_default "50°C threshold fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_50" "TEMP_THRESHOLD_50" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
        prompt_with_default "Default fan speed (0-255)" "$DEFAULT_TEMP_THRESHOLD_DEFAULT" "TEMP_THRESHOLD_DEFAULT" false "^([0-9]|[1-9][0-9]|1[0-9][0-9]|2[0-4][0-9]|25[0-5])$" "Please enter a number between 0 and 255"
    else
        # Use current/default values
        TEMP_THRESHOLD_90="$DEFAULT_TEMP_THRESHOLD_90"
        TEMP_THRESHOLD_80="$DEFAULT_TEMP_THRESHOLD_80"
        TEMP_THRESHOLD_70="$DEFAULT_TEMP_THRESHOLD_70"
        TEMP_THRESHOLD_60="$DEFAULT_TEMP_THRESHOLD_60"
        TEMP_THRESHOLD_50="$DEFAULT_TEMP_THRESHOLD_50"
        TEMP_THRESHOLD_DEFAULT="$DEFAULT_TEMP_THRESHOLD_DEFAULT"
    fi
    echo ""

    # Dynamic control settings
    print_color "$CYAN" "=== Dynamic Fan Control Settings ==="
    prompt_yes_no "Enable dynamic temperature-based fan control" "$DEFAULT_ENABLE_DYNAMIC_CONTROL" "ENABLE_DYNAMIC_CONTROL"

    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        prompt_with_default "Temperature monitoring interval (seconds)" "$DEFAULT_MONITORING_INTERVAL" "MONITORING_INTERVAL" false "^[0-9]+$" "Please enter a number"
        
        echo "CPU1 fan assignments (space-separated, e.g., 3 4 5):"
        prompt_with_default "CPU1 fans" "$DEFAULT_CPU1_FANS_INPUT" "CPU1_FANS_INPUT"
        
        echo "CPU2 fan assignments (space-separated, e.g., 0 1 2):"
        prompt_with_default "CPU2 fans" "$DEFAULT_CPU2_FANS_INPUT" "CPU2_FANS_INPUT"
        
        prompt_with_default "Maximum safe CPU temperature (°C)" "$DEFAULT_MAX_TEMP_CPU" "MAX_TEMP_CPU" false "^[0-9]+$" "Please enter a number"
    else
        MONITORING_INTERVAL="$DEFAULT_MONITORING_INTERVAL"
        CPU1_FANS_INPUT="$DEFAULT_CPU1_FANS_INPUT"
        CPU2_FANS_INPUT="$DEFAULT_CPU2_FANS_INPUT"
        MAX_TEMP_CPU="$DEFAULT_MAX_TEMP_CPU"
    fi
    echo ""

    # Advanced settings
    print_color "$CYAN" "=== Advanced Settings ==="
    prompt_with_default "Log level (DEBUG/INFO/WARN/ERROR)" "$DEFAULT_LOG_LEVEL" "LOG_LEVEL" false "^(DEBUG|INFO|WARN|ERROR)$" "Please enter DEBUG, INFO, WARN, or ERROR"
    prompt_with_default "Connection timeout (seconds)" "$DEFAULT_CONNECTION_TIMEOUT" "CONNECTION_TIMEOUT" false "^[0-9]+$" "Please enter a number"
    prompt_with_default "Command retries" "$DEFAULT_COMMAND_RETRIES" "COMMAND_RETRIES" false "^[0-9]+$" "Please enter a number"
    echo ""
}

# Function to show configuration summary
show_configuration_summary() {
    print_color "$CYAN" "Configuration Summary:"
    print_color "$GREEN" "  iLO Host: $ILO_HOST"
    print_color "$GREEN" "  iLO User: $ILO_USER"
    print_color "$GREEN" "  Fan Count: $FAN_COUNT"
    print_color "$GREEN" "  Min Speed: $GLOBAL_MIN_SPEED"
    print_color "$GREEN" "  Dynamic Control: $ENABLE_DYNAMIC_CONTROL"
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        print_color "$GREEN" "  Monitor Interval: ${MONITORING_INTERVAL}s"
        print_color "$GREEN" "  Max CPU Temperature: ${MAX_TEMP_CPU}°C"
    fi
    print_color "$GREEN" "  Log Level: $LOG_LEVEL"
    echo ""
}

# Main execution flow
main() {
    # Show header
    show_header
    
    # Detect OS
    detect_os
    
    # Check prerequisites
    check_prerequisites
    
    # Collect configuration
    collect_configuration
    
    # Show configuration summary
    show_configuration_summary
    
    # Confirm installation
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_color "$YELLOW" "Installation cancelled."
        exit 0
    fi
    
    # Install packages
    install_packages
    
    # Create directories
    create_directories
    
    # Download and configure files
    download_and_configure_files
    
    # Install systemd service
    install_systemd_service
    
    # Test configuration
    test_configuration
    
    # Show completion message
    show_completion_message
}

# Function to install packages
install_packages() {
    print_color "$BLUE" "Step 1: Checking and installing dependencies..."

    # Function to check if package is installed
    is_package_installed() {
        dpkg -l "$1" &> /dev/null
    }

    # List of required packages
    REQUIRED_PACKAGES=("sshpass" "openssh-client" "wget" "curl")
    OPTIONAL_PACKAGES=("lm-sensors" "jq" "bc")  # For temperature monitoring

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
        print_color "$YELLOW" "Installing missing packages: ${MISSING_PACKAGES[*]}"
        $SUDO_CMD apt update
        $SUDO_CMD apt install -y "${MISSING_PACKAGES[@]}"
        print_color "$GREEN" "✓ Packages installed successfully"
    else
        print_color "$GREEN" "✓ All required packages are already installed"
    fi
    echo ""
}

# Function to create directories
create_directories() {
    print_color "$BLUE" "Step 2: Creating directories..."
    
    $SUDO_CMD mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR"
    
    print_color "$GREEN" "✓ Directories created successfully"
    echo ""
}

# Function to download and configure files
download_and_configure_files() {
    print_color "$BLUE" "Step 3: Downloading and configuring files..."
    
    # Download main script
    print_color "$YELLOW" "Downloading main script..."
    if ! wget -q "$SCRIPT_URL" -O /tmp/ilo4-fan-control.sh; then
        print_color "$RED" "ERROR: Failed to download fan control script"
        print_color "$RED" "URL: $SCRIPT_URL"
        exit 1
    fi
    
    # Download configuration template
    print_color "$YELLOW" "Downloading configuration template..."
    if ! wget -q "$CONFIG_URL" -O /tmp/ilo4-fan-control.conf; then
        print_color "$RED" "ERROR: Failed to download configuration template"
        print_color "$RED" "URL: $CONFIG_URL"
        exit 1
    fi
    
    # Download manual control script
    print_color "$YELLOW" "Downloading manual control script..."
    if ! wget -q "$MANUAL_SCRIPT_URL" -O /tmp/ilo4-fan-control-manual.sh; then
        print_color "$YELLOW" "Warning: Failed to download manual script (continuing without it)"
    fi
    
    # Configure the main configuration file
    print_color "$YELLOW" "Configuring system..."
    
    # Process arrays for configuration
    DISABLED_SENSORS_ARRAY="($(echo "$DISABLED_SENSORS_INPUT" | sed 's/,/ /g'))"
    CPU1_FANS_ARRAY="($CPU1_FANS_INPUT)"
    CPU2_FANS_ARRAY="($CPU2_FANS_INPUT)"
    
    # Update configuration file
    sed -i "s|ILO_HOST=\".*\"|ILO_HOST=\"$ILO_HOST\"|g" /tmp/ilo4-fan-control.conf
    sed -i "s|ILO_USER=\".*\"|ILO_USER=\"$ILO_USER\"|g" /tmp/ilo4-fan-control.conf
    sed -i "s|ILO_PASS=\".*\"|ILO_PASS=\"$ILO_PASS\"|g" /tmp/ilo4-fan-control.conf
    sed -i "s|FAN_COUNT=.*|FAN_COUNT=$FAN_COUNT|g" /tmp/ilo4-fan-control.conf
    sed -i "s|GLOBAL_MIN_SPEED=.*|GLOBAL_MIN_SPEED=$GLOBAL_MIN_SPEED|g" /tmp/ilo4-fan-control.conf
    sed -i "s|PID_MIN_LOW=.*|PID_MIN_LOW=$PID_MIN_LOW|g" /tmp/ilo4-fan-control.conf
    sed -i "s|DISABLED_SENSORS=.*|DISABLED_SENSORS=$DISABLED_SENSORS_ARRAY|g" /tmp/ilo4-fan-control.conf
    sed -i "s|ENABLE_DYNAMIC_CONTROL=.*|ENABLE_DYNAMIC_CONTROL=$ENABLE_DYNAMIC_CONTROL|g" /tmp/ilo4-fan-control.conf
    sed -i "s|MONITORING_INTERVAL=.*|MONITORING_INTERVAL=$MONITORING_INTERVAL|g" /tmp/ilo4-fan-control.conf
    sed -i "s|CPU1_FANS=.*|CPU1_FANS=$CPU1_FANS_ARRAY|g" /tmp/ilo4-fan-control.conf
    sed -i "s|CPU2_FANS=.*|CPU2_FANS=$CPU2_FANS_ARRAY|g" /tmp/ilo4-fan-control.conf
    sed -i "s|MAX_TEMP_CPU=.*|MAX_TEMP_CPU=$MAX_TEMP_CPU|g" /tmp/ilo4-fan-control.conf
    sed -i "s|LOG_LEVEL=.*|LOG_LEVEL=\"$LOG_LEVEL\"|g" /tmp/ilo4-fan-control.conf
    sed -i "s|CONNECTION_TIMEOUT=.*|CONNECTION_TIMEOUT=$CONNECTION_TIMEOUT|g" /tmp/ilo4-fan-control.conf
    sed -i "s|COMMAND_RETRIES=.*|COMMAND_RETRIES=$COMMAND_RETRIES|g" /tmp/ilo4-fan-control.conf
    
    # Update temperature thresholds
    sed -i "s|TEMP_THRESHOLD_90=.*|TEMP_THRESHOLD_90=$TEMP_THRESHOLD_90|g" /tmp/ilo4-fan-control.conf
    sed -i "s|TEMP_THRESHOLD_80=.*|TEMP_THRESHOLD_80=$TEMP_THRESHOLD_80|g" /tmp/ilo4-fan-control.conf
    sed -i "s|TEMP_THRESHOLD_70=.*|TEMP_THRESHOLD_70=$TEMP_THRESHOLD_70|g" /tmp/ilo4-fan-control.conf
    sed -i "s|TEMP_THRESHOLD_60=.*|TEMP_THRESHOLD_60=$TEMP_THRESHOLD_60|g" /tmp/ilo4-fan-control.conf
    sed -i "s|TEMP_THRESHOLD_50=.*|TEMP_THRESHOLD_50=$TEMP_THRESHOLD_50|g" /tmp/ilo4-fan-control.conf
    sed -i "s|TEMP_THRESHOLD_DEFAULT=.*|TEMP_THRESHOLD_DEFAULT=$TEMP_THRESHOLD_DEFAULT|g" /tmp/ilo4-fan-control.conf
    
    # Install files
    $SUDO_CMD mv /tmp/ilo4-fan-control.sh "$INSTALL_DIR/ilo4-fan-control.sh"
    $SUDO_CMD mv /tmp/ilo4-fan-control.conf "$CONFIG_DIR/ilo4-fan-control.conf"
    $SUDO_CMD chmod +x "$INSTALL_DIR/ilo4-fan-control.sh"
    
    # Install manual script if downloaded
    if [[ -f /tmp/ilo4-fan-control-manual.sh ]]; then
        $SUDO_CMD mv /tmp/ilo4-fan-control-manual.sh "$INSTALL_DIR/ilo4-fan-control-manual.sh"
        $SUDO_CMD chmod +x "$INSTALL_DIR/ilo4-fan-control-manual.sh"
        print_color "$GREEN" "✓ Manual control script installed"
    fi
    
    print_color "$GREEN" "✓ Files downloaded and configured successfully"
    echo ""
}

# Function to install systemd service
install_systemd_service() {
    print_color "$BLUE" "Step 4: Installing systemd service..."
    
    # Download service file
    if ! wget -q "$SERVICE_URL" -O /tmp/ilo4-fan-control.service; then
        print_color "$RED" "ERROR: Failed to download service file"
        print_color "$RED" "URL: $SERVICE_URL"
        exit 1
    fi
    
    # Install service file
    $SUDO_CMD mv /tmp/ilo4-fan-control.service "$SERVICE_DIR/ilo4-fan-control.service"
    
    # Reload systemd and enable service
    $SUDO_CMD systemctl daemon-reload
    $SUDO_CMD systemctl enable ilo4-fan-control.service
    
    print_color "$GREEN" "✓ Systemd service installed and enabled"
    echo ""
}

# Function to test configuration
test_configuration() {
    print_color "$BLUE" "Step 5: Testing configuration..."
    
    # Test SSH connection
    print_color "$YELLOW" "Testing SSH connection to iLO..."
    if timeout 10 sshpass -p "$ILO_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$ILO_USER@$ILO_HOST" "version" &>/dev/null; then
        print_color "$GREEN" "✓ SSH connection to iLO successful"
        
        # Test script execution
        print_color "$YELLOW" "Running configuration test..."
        if $SUDO_CMD timeout 60 "$INSTALL_DIR/ilo4-fan-control.sh" --test-mode &>/dev/null; then
            print_color "$GREEN" "✓ Script configuration test completed successfully"
        else
            print_color "$YELLOW" "⚠ Script test had issues, but installation completed"
            print_color "$YELLOW" "Check the logs after starting the service for more details"
        fi
    else
        print_color "$YELLOW" "⚠ SSH connection test failed"
        print_color "$YELLOW" "Please verify iLO credentials and network connectivity"
        print_color "$YELLOW" "The service is installed but may not work until connection issues are resolved"
    fi
    echo ""
}

# Function to show completion message
show_completion_message() {
    print_color "$GREEN" "=========================================="
    print_color "$GREEN" "Installation Complete!"
    print_color "$GREEN" "=========================================="
    echo ""
    
    print_color "$CYAN" "Installed Files:"
    print_color "$BLUE" "  Main script: $INSTALL_DIR/ilo4-fan-control.sh"
    print_color "$BLUE" "  Configuration: $CONFIG_DIR/ilo4-fan-control.conf"
    print_color "$BLUE" "  Service file: $SERVICE_DIR/ilo4-fan-control.service"
    if [[ -f "$INSTALL_DIR/ilo4-fan-control-manual.sh" ]]; then
        print_color "$BLUE" "  Manual control: $INSTALL_DIR/ilo4-fan-control-manual.sh"
    fi
    print_color "$BLUE" "  Log file: $LOG_DIR/ilo4-fan-control.log"
    echo ""
    
    print_color "$CYAN" "Configuration Applied:"
    print_color "$GREEN" "  iLO Host: $ILO_HOST"
    print_color "$GREEN" "  iLO User: $ILO_USER"
    print_color "$GREEN" "  Fan Count: $FAN_COUNT"
    print_color "$GREEN" "  Min Speed: $GLOBAL_MIN_SPEED"
    print_color "$GREEN" "  Dynamic Control: $ENABLE_DYNAMIC_CONTROL"
    print_color "$GREEN" "  Log Level: $LOG_LEVEL"
    echo ""
    
    print_color "$CYAN" "Service Management Commands:"
    print_color "$YELLOW" "  Start service:    ${SUDO_CMD} systemctl start ilo4-fan-control"
    print_color "$YELLOW" "  Stop service:     ${SUDO_CMD} systemctl stop ilo4-fan-control"
    print_color "$YELLOW" "  Check status:     ${SUDO_CMD} systemctl status ilo4-fan-control"
    print_color "$YELLOW" "  View logs:        ${SUDO_CMD} journalctl -u ilo4-fan-control -f"
    print_color "$YELLOW" "  View script logs: ${SUDO_CMD} tail -f $LOG_DIR/ilo4-fan-control.log"
    echo ""
    
    print_color "$CYAN" "Configuration Management:"
    print_color "$YELLOW" "  Edit config:      ${SUDO_CMD} nano $CONFIG_DIR/ilo4-fan-control.conf"
    print_color "$YELLOW" "  Restart service:  ${SUDO_CMD} systemctl restart ilo4-fan-control"
    print_color "$YELLOW" "  Reload config:    ${SUDO_CMD} systemctl reload ilo4-fan-control"
    echo ""
    
    if [[ -f "$INSTALL_DIR/ilo4-fan-control-manual.sh" ]]; then
        print_color "$CYAN" "Manual Control:"
        print_color "$YELLOW" "  Interactive mode: ${SUDO_CMD} $INSTALL_DIR/ilo4-fan-control-manual.sh --interactive"
        print_color "$YELLOW" "  Check status:     ${SUDO_CMD} $INSTALL_DIR/ilo4-fan-control-manual.sh --status"
        print_color "$YELLOW" "  Emergency mode:   ${SUDO_CMD} $INSTALL_DIR/ilo4-fan-control-manual.sh --emergency"
        echo ""
    fi
    
    print_color "$GREEN" "The service is enabled and will start automatically on boot."
    print_color "$GREEN" "To start it now, run: ${SUDO_CMD} systemctl start ilo4-fan-control"
    echo ""
    
    print_color "$YELLOW" "If you need to modify the configuration later:"
    print_color "$YELLOW" "1. Edit the configuration file: $CONFIG_DIR/ilo4-fan-control.conf"
    print_color "$YELLOW" "2. Restart the service: ${SUDO_CMD} systemctl restart ilo4-fan-control"
    echo ""
    
    print_color "$CYAN" "For troubleshooting, check:"
    print_color "$BLUE" "  - Service status: ${SUDO_CMD} systemctl status ilo4-fan-control"
    print_color "$BLUE" "  - System logs: ${SUDO_CMD} journalctl -u ilo4-fan-control --since '1 hour ago'"
    print_color "$BLUE" "  - Script logs: ${SUDO_CMD} tail -f $LOG_DIR/ilo4-fan-control.log"
    echo ""
}

# Execute main function
main "$@"
