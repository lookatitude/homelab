#!/bin/bash

# iLO4 Fan Control Installation Script for Proxmox/Debian
# This script downloads, configures, and installs the iLO4 fan control service
# Usage: bash -c "$(curl -fsSL https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4/install.sh)"

set -euo pipefail

# Script version and info
SCRIPT_VERSION="2.1.0"
INSTALLER_NAME="iLO4 Fan Control Installer"

# Repository configuration
REPO_BASE_URL="https://raw.githubusercontent.com/lookatitude/homelab/main/proxmox/ilo4"
SCRIPT_URL="$REPO_BASE_URL/ilo4-fan-control.sh"
SERVICE_URL="$REPO_BASE_URL/ilo4-fan-control.service"
CONFIG_URL="$REPO_BASE_URL/ilo4-fan-control.conf"
MANUAL_SCRIPT_URL="$REPO_BASE_URL/ilo4-fan-control-manual.sh"
THRESHOLDS_SCRIPT_URL="$REPO_BASE_URL/set-thresholds.sh"

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
        
        # Suggest installation commands based on OS
        if command -v apt-get &> /dev/null; then
            print_color "$YELLOW" "Run: apt-get update && apt-get install -y ${missing_commands[*]}"
        elif command -v yum &> /dev/null; then
            print_color "$YELLOW" "Run: yum install -y ${missing_commands[*]}"
        fi
        exit 1
    fi
    
    # Check if systemd is running
    if ! systemctl is-system-running &>/dev/null; then
        print_color "$YELLOW" "⚠ Warning: systemd may not be running properly"
    fi
    
    print_color "$GREEN" "✓ Prerequisites check passed"
    echo ""
}

# Function to check for sudo/root privileges
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
        print_color "$YELLOW" "⚠ Running as root"
    elif command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        SUDO_CMD="sudo"
        print_color "$GREEN" "✓ Sudo access available"
    else
        print_color "$RED" "✗ This script requires root privileges or sudo access"
        print_color "$YELLOW" "Please run as root or ensure sudo is available and configured"
        exit 1
    fi
    echo ""
}

# Ensure all commands dynamically avoid using sudo when running as root
create_directories() {
    print_color "$BLUE" "Step 3: Creating directories..."

    if ! $SUDO_CMD mkdir -p "$CONFIG_DIR"; then
        print_color "$RED" "✗ Failed to create configuration directory: $CONFIG_DIR"
        exit 1
    fi

    if ! $SUDO_CMD mkdir -p "$LOG_DIR"; then
        print_color "$RED" "✗ Failed to create log directory: $LOG_DIR"
        exit 1
    fi

    print_color "$GREEN" "✓ Directories created"
    echo ""
}

# Function to download and install files
# Update all commands to dynamically avoid using sudo when running as root
download_and_install_files() {
    print_color "$BLUE" "Step 4: Downloading and installing files..."
    
    # Download main script
    print_color "$YELLOW" "Downloading main script..."
    if curl -fsSL "$SCRIPT_URL" -o "/tmp/ilo4-fan-control.sh"; then
        $SUDO_CMD mv -f "/tmp/ilo4-fan-control.sh" "$INSTALL_DIR/ilo4-fan-control.sh"
        $SUDO_CMD chmod +x "$INSTALL_DIR/ilo4-fan-control.sh"
        print_color "$GREEN" "✓ Main script installed"
    else
        print_color "$RED" "✗ Failed to download main script"
        exit 1
    fi
    
    # Download service file
    print_color "$YELLOW" "Downloading service file..."
    if curl -fsSL "$SERVICE_URL" -o "/tmp/ilo4-fan-control.service"; then
        $SUDO_CMD mv -f "/tmp/ilo4-fan-control.service" "$SERVICE_DIR/ilo4-fan-control.service"
        print_color "$GREEN" "✓ Service file installed"
    else
        print_color "$RED" "✗ Failed to download service file"
        exit 1
    fi
    
    # Download manual control script (optional)
    print_color "$YELLOW" "Downloading manual control script..."
    if curl -fsSL "$MANUAL_SCRIPT_URL" -o "/tmp/ilo4-fan-control-manual.sh"; then
        $SUDO_CMD mv -f "/tmp/ilo4-fan-control-manual.sh" "$INSTALL_DIR/ilo4-fan-control-manual.sh"
        $SUDO_CMD chmod +x "$INSTALL_DIR/ilo4-fan-control-manual.sh"
        print_color "$GREEN" "✓ Manual control script installed"
    else
        print_color "$YELLOW" "⚠ Manual control script not available (optional)"
    fi
    
    # Download threshold management script (optional)
    print_color "$YELLOW" "Downloading threshold management script..."
    if curl -fsSL "$THRESHOLDS_SCRIPT_URL" -o "/tmp/set-thresholds.sh"; then
        $SUDO_CMD mv -f "/tmp/set-thresholds.sh" "$INSTALL_DIR/set-thresholds.sh"
        $SUDO_CMD chmod +x "$INSTALL_DIR/set-thresholds.sh"
        print_color "$GREEN" "✓ Threshold management script installed"
    else
        print_color "$YELLOW" "⚠ Threshold management script not available (optional)"
    fi
    
    print_color "$GREEN" "✓ All files downloaded and installed successfully"
    echo ""
}

# Ensure the configuration file path is consistently checked
load_existing_config() {
    local config_file="/etc/ilo4-fan-control/ilo4-fan-control.conf"

    print_color "$BLUE" "Debug: Checking if configuration file exists"
    if [[ -f "$config_file" ]]; then
        print_color "$GREEN" "✓ Configuration file found"

        # Extract existing values
        EXISTING_ILO_HOST=$(grep '^ILO_HOST=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_ILO_USER=$(grep '^ILO_USER=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_ILO_PASS=$(grep '^ILO_PASS=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_ENABLE_DYNAMIC_CONTROL=$(grep '^ENABLE_DYNAMIC_CONTROL=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_LOG_LEVEL=$(grep '^LOG_LEVEL=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_MONITORING_INTERVAL=$(grep '^MONITORING_INTERVAL=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_FAN_COUNT=$(grep '^FAN_COUNT=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')
        EXISTING_GLOBAL_MIN_SPEED=$(grep '^GLOBAL_MIN_SPEED=' "$config_file" 2>/dev/null | cut -d'=' -f2 | tr -d '"')

        # Debugging: Print loaded values
        print_color "$CYAN" "Debug: Loaded values from configuration file"
        print_color "$CYAN" "  iLO Host: $EXISTING_ILO_HOST"
        print_color "$CYAN" "  iLO User: $EXISTING_ILO_USER"
        print_color "$CYAN" "  iLO Password: [hidden]"
        print_color "$CYAN" "  Enable Dynamic Control: $EXISTING_ENABLE_DYNAMIC_CONTROL"
        print_color "$CYAN" "  Log Level: $EXISTING_LOG_LEVEL"
        print_color "$CYAN" "  Monitoring Interval: $EXISTING_MONITORING_INTERVAL"
        print_color "$CYAN" "  Fan Count: $EXISTING_FAN_COUNT"
        print_color "$CYAN" "  Global Min Speed: $EXISTING_GLOBAL_MIN_SPEED"

        return 0
    else
        print_color "$RED" "✗ Configuration file not found"
        return 1
    fi
}

# Function to set default values
# Ensure all variables are initialized in set_default_values
set_default_values() {
    # Set defaults (use existing values if available, otherwise use installer defaults)
    DEFAULT_ILO_HOST="${EXISTING_ILO_HOST:-<ip>}"
    DEFAULT_ILO_USER="${EXISTING_ILO_USER:-<username>}"
    DEFAULT_FAN_COUNT="${EXISTING_FAN_COUNT:-6}"
    DEFAULT_GLOBAL_MIN_SPEED="${EXISTING_GLOBAL_MIN_SPEED:-60}"
    DEFAULT_ENABLE_DYNAMIC_CONTROL="${EXISTING_ENABLE_DYNAMIC_CONTROL:-true}"
    DEFAULT_LOG_LEVEL="${EXISTING_LOG_LEVEL:-INFO}"
    DEFAULT_MONITORING_INTERVAL="${EXISTING_MONITORING_INTERVAL:-30}"
    MAX_TEMP_CPU="${MAX_TEMP_CPU:-80}"
    EMERGENCY_SPEED="${EMERGENCY_SPEED:-255}"
    CONNECTION_TIMEOUT="${CONNECTION_TIMEOUT:-30}"
    COMMAND_RETRIES="${COMMAND_RETRIES:-3}"
    MAX_LOG_SIZE="${MAX_LOG_SIZE:-50M}"
    LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-30}"
    NETWORK_CHECK_RETRIES="${NETWORK_CHECK_RETRIES:-30}"
    NETWORK_CHECK_INTERVAL="${NETWORK_CHECK_INTERVAL:-2}"
    SSH_ALIVE_INTERVAL="${SSH_ALIVE_INTERVAL:-10}"
    SSH_ALIVE_COUNT_MAX="${SSH_ALIVE_COUNT_MAX:-3}"
}

# Update configure_settings to ensure comments are excluded from prompts
configure_settings() {
    print_color "$BLUE" "Step 2: Configuration Settings"
    print_color "$BLUE" "Please provide the following information:"
    echo ""

    # iLO Host
    while true; do
        read -p "Enter iLO IP address or hostname [$DEFAULT_ILO_HOST]: " ILO_HOST
        ILO_HOST=${ILO_HOST:-$DEFAULT_ILO_HOST}
        if [[ "$ILO_HOST" != "<ip>" ]] && [[ -n "$ILO_HOST" ]]; then
            break
        else
            print_color "$RED" "Please enter a valid iLO IP address or hostname"
        fi
    done

    # iLO User
    while true; do
        read -p "Enter iLO username [$DEFAULT_ILO_USER]: " ILO_USER
        ILO_USER=${ILO_USER:-$DEFAULT_ILO_USER}
        if [[ "$ILO_USER" != "<username>" ]] && [[ -n "$ILO_USER" ]]; then
            break
        else
            print_color "$RED" "Please enter a valid iLO username"
        fi
    done

    # iLO Password
    while true; do
        read -s -p "Enter iLO password: " ILO_PASS
        echo ""
        if [[ -n "$ILO_PASS" ]]; then
            read -s -p "Confirm iLO password: " ILO_PASS_CONFIRM
            echo ""
            if [[ "$ILO_PASS" == "$ILO_PASS_CONFIRM" ]]; then
                break
            else
                print_color "$RED" "Passwords do not match. Please try again."
            fi
        else
            print_color "$RED" "Password cannot be empty"
        fi
    done

    # Fan Count
    read -p "Enter number of fans [$DEFAULT_FAN_COUNT]: " FAN_COUNT
    FAN_COUNT=${FAN_COUNT:-$DEFAULT_FAN_COUNT}

    # Global Minimum Speed
    read -p "Enter global minimum fan speed (0-255) [$DEFAULT_GLOBAL_MIN_SPEED]: " GLOBAL_MIN_SPEED
    GLOBAL_MIN_SPEED=${GLOBAL_MIN_SPEED:-$DEFAULT_GLOBAL_MIN_SPEED}

    # Dynamic Control
    read -p "Enable dynamic temperature control? (true/false) [$DEFAULT_ENABLE_DYNAMIC_CONTROL]: " ENABLE_DYNAMIC_CONTROL
    ENABLE_DYNAMIC_CONTROL=${ENABLE_DYNAMIC_CONTROL:-$DEFAULT_ENABLE_DYNAMIC_CONTROL}

    # Monitoring Interval
    read -p "Temperature monitoring interval (seconds) [$DEFAULT_MONITORING_INTERVAL]: " MONITORING_INTERVAL
    MONITORING_INTERVAL=${MONITORING_INTERVAL:-$DEFAULT_MONITORING_INTERVAL}

    # Log Level
    read -p "Log level (DEBUG/INFO/WARN/ERROR) [$DEFAULT_LOG_LEVEL]: " LOG_LEVEL
    LOG_LEVEL=${LOG_LEVEL:-$DEFAULT_LOG_LEVEL}

    # Additional configurations
    read -p "Maximum safe CPU temperature [$MAX_TEMP_CPU]: " MAX_TEMP_CPU
    MAX_TEMP_CPU=${MAX_TEMP_CPU:-80}

    read -p "Emergency fan speed [$EMERGENCY_SPEED]: " EMERGENCY_SPEED
    EMERGENCY_SPEED=${EMERGENCY_SPEED:-255}

    read -p "SSH connection timeout (seconds) [$CONNECTION_TIMEOUT]: " CONNECTION_TIMEOUT
    CONNECTION_TIMEOUT=${CONNECTION_TIMEOUT:-30}

    read -p "Number of retries for failed commands [$COMMAND_RETRIES]: " COMMAND_RETRIES
    COMMAND_RETRIES=${COMMAND_RETRIES:-3}

    read -p "Maximum log file size [$MAX_LOG_SIZE]: " MAX_LOG_SIZE
    MAX_LOG_SIZE=${MAX_LOG_SIZE:-"50M"}

    read -p "Days to keep old log files [$LOG_RETENTION_DAYS]: " LOG_RETENTION_DAYS
    LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}

    read -p "Retries for network connectivity check [$NETWORK_CHECK_RETRIES]: " NETWORK_CHECK_RETRIES
    NETWORK_CHECK_RETRIES=${NETWORK_CHECK_RETRIES:-30}

    read -p "Seconds between network checks [$NETWORK_CHECK_INTERVAL]: " NETWORK_CHECK_INTERVAL
    NETWORK_CHECK_INTERVAL=${NETWORK_CHECK_INTERVAL:-2}

    read -p "SSH keep-alive interval [$SSH_ALIVE_INTERVAL]: " SSH_ALIVE_INTERVAL
    SSH_ALIVE_INTERVAL=${SSH_ALIVE_INTERVAL:-10}

    read -p "Maximum SSH keep-alive failures [$SSH_ALIVE_COUNT_MAX]: " SSH_ALIVE_COUNT_MAX
    SSH_ALIVE_COUNT_MAX=${SSH_ALIVE_COUNT_MAX:-3}

    echo ""
    print_color "$GREEN" "✓ Configuration settings collected"
    echo ""
}

# Function to create configuration file
# Update the `create_configuration_file` function to place comments on separate lines
create_configuration_file() {
    print_color "$BLUE" "Creating configuration file..."

    local config_file="$CONFIG_DIR/ilo4-fan-control.conf"

    # Create configuration file with user settings
    cat << EOF | sudo tee "$config_file" > /dev/null
# iLO4 Fan Control Configuration File
# This file contains the configuration for the iLO4 fan control system
# Edit this file to customize your setup, then restart the service

# === iLO CONNECTION SETTINGS ===
# iLO IP address or hostname
ILO_HOST="$ILO_HOST"

# iLO username
ILO_USER="$ILO_USER"

# iLO password
ILO_PASS="$ILO_PASS"

# Set to false to use SSH key authentication
USE_SSH_PASS=true

# === FAN CONFIGURATION ===
# Total number of fans (0 to FAN_COUNT-1)
FAN_COUNT=$FAN_COUNT

# Minimum fan speed (0-255)
GLOBAL_MIN_SPEED=$GLOBAL_MIN_SPEED

# PID minimum low value
PID_MIN_LOW=1600

# Sensor IDs to disable (space-separated)
DISABLED_SENSORS=(07FB00 35 38)

# === DYNAMIC CONTROL SETTINGS ===
# Enable temperature-based fan control
ENABLE_DYNAMIC_CONTROL=$ENABLE_DYNAMIC_CONTROL

# Seconds between temperature checks
MONITORING_INTERVAL=$MONITORING_INTERVAL

# Fans controlled by CPU1 temperature
CPU1_FANS=(3 4 5)

# Fans controlled by CPU2 temperature
CPU2_FANS=(0 1 2)

# === TEMPERATURE THRESHOLDS ===
# Temperature breakpoints (highest to lowest)
TEMP_STEPS=(90 80 70 60 50)

# Fan speeds for each temperature step (0-255)
TEMP_THRESHOLD_90=255
TEMP_THRESHOLD_80=200
TEMP_THRESHOLD_70=150
TEMP_THRESHOLD_60=100
TEMP_THRESHOLD_50=75
TEMP_THRESHOLD_DEFAULT=50

# === SAFETY AND MONITORING ===
# Maximum safe CPU temperature
MAX_TEMP_CPU=80

# Fan speed for emergency situations
EMERGENCY_SPEED=255

# SSH connection timeout in seconds
CONNECTION_TIMEOUT=30

# Number of retries for failed commands
COMMAND_RETRIES=3

# === LOGGING ===
# Log level: DEBUG, INFO, WARN, ERROR
LOG_LEVEL="$LOG_LEVEL"

LOG_FILE="/var/log/ilo4-fan-control.log"
EOF

    chmod 600 "$config_file"
    print_color "$GREEN" "✓ Configuration file created"
    echo ""
}



# Function to test configuration
test_configuration() {
    print_color "$BLUE" "Step 5: Testing configuration..."
    
    # Test SSH connection to iLO
    print_color "$YELLOW" "Testing SSH connection to iLO..."
    if timeout 30 sshpass -p "$ILO_PASS" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$ILO_USER@$ILO_HOST" "exit" &>/dev/null; then
        print_color "$GREEN" "✓ SSH connection to iLO successful"
        
        # Test script execution
        print_color "$YELLOW" "Running configuration test..."
        if sudo timeout 60 "$INSTALL_DIR/ilo4-fan-control.sh" --test-mode &>/dev/null; then
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

# Function to configure systemd service
configure_service() {
    print_color "$BLUE" "Step 6: Configuring systemd service..."
    
    # Reload systemd
    $SUDO_CMD systemctl daemon-reload
    
    # Enable the service
    $SUDO_CMD systemctl enable ilo4-fan-control.service
    
    print_color "$GREEN" "✓ Service configured and enabled"
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
    if [[ -f "$INSTALL_DIR/set-thresholds.sh" ]]; then
        print_color "$BLUE" "  Threshold manager: $INSTALL_DIR/set-thresholds.sh"
    fi
    print_color "$BLUE" "  Log file: $LOG_DIR/ilo4-fan-control.log"
    echo ""
    print_color "$CYAN" "Configuration Applied:"
    MASKED_PASS="$(echo "$ILO_PASS" | sed 's/./*/g')"
    print_color "$GREEN" "  iLO Host: $ILO_HOST"
    print_color "$GREEN" "  iLO User: $ILO_USER"
    print_color "$GREEN" "  iLO Password: $MASKED_PASS"
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
    
    if [[ -f "$INSTALL_DIR/set-thresholds.sh" ]]; then
        print_color "$CYAN" "Temperature Threshold Management:"
        print_color "$YELLOW" "  List thresholds:  ${SUDO_CMD} $INSTALL_DIR/set-thresholds.sh --list-temp-steps"
        print_color "$YELLOW" "  Add threshold:    ${SUDO_CMD} $INSTALL_DIR/set-thresholds.sh --add-temp-step TEMP SPEED"
        print_color "$YELLOW" "  Remove threshold: ${SUDO_CMD} $INSTALL_DIR/set-thresholds.sh --remove-temp-step TEMP"
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

# Function to warn about root access and get confirmation
warn_root_access() {
    if [[ $EUID -eq 0 ]]; then
        print_color "$YELLOW" "=========================================="
        print_color "$YELLOW" "⚠  ROOT ACCESS WARNING ⚠"
        print_color "$YELLOW" "=========================================="
        print_color "$RED" "You are running this installer as root!"
        print_color "$YELLOW" "While this is not necessarily dangerous, it's recommended to:"
        print_color "$YELLOW" "• Run as a regular user with sudo access"
        print_color "$YELLOW" "• Only use root when absolutely necessary"
        echo ""
        print_color "$BLUE" "This installer will:"
        print_color "$BLUE" "• Install files to system directories"
        print_color "$BLUE" "• Create/modify configuration files"
        print_color "$BLUE" "• Install and configure systemd services"
        print_color "$BLUE" "• Install dependencies if needed"
        echo ""
        
        while true; do
            read -p "Do you want to continue running as root? (y/n): " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                print_color "$GREEN" "Continuing with root access..."
                echo ""
                break
            elif [[ $REPLY =~ ^[Nn]$ ]]; then
                print_color "$YELLOW" "Installation cancelled by user."
                print_color "$BLUE" "To run as regular user: exit and run without sudo/root"
                exit 0
            else
                print_color "$RED" "Please answer y or n"
            fi
        done
    fi
}

# Function to install dependencies
install_dependencies() {
    print_color "$BLUE" "Checking and installing dependencies..."
    
    local packages_to_install=()
    local required_packages=("wget" "curl")
    
    # Check which packages are missing
    for package in "${required_packages[@]}"; do
        if ! command -v "$package" &> /dev/null; then
            packages_to_install+=("$package")
        fi
    done
    
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        print_color "$YELLOW" "Installing missing packages: ${packages_to_install[*]}"
        
        if command -v apt-get &> /dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${packages_to_install[@]}"
        elif command -v yum &> /dev/null; then
            sudo yum install -y "${packages_to_install[@]}"
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y "${packages_to_install[@]}"
        else
            print_color "$RED" "✗ Cannot install packages automatically on this system"
            print_color "$YELLOW" "Please install these packages manually: ${packages_to_install[*]}"
            exit 1
        fi
        
        # Verify installation
        local failed_packages=()
        for package in "${packages_to_install[@]}"; do
            if ! command -v "$package" &> /dev/null; then
                failed_packages+=("$package")
            fi
        done
        
        if [[ ${#failed_packages[@]} -gt 0 ]]; then
            print_color "$RED" "✗ Failed to install: ${failed_packages[*]}"
            exit 1
        else
            print_color "$GREEN" "✓ All dependencies installed successfully"
        fi
    else
        print_color "$GREEN" "✓ All dependencies are already installed"
    fi
    echo ""
}

# Define a simple logging function
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$timestamp] [$level] $message"
}

# Function to update scripts
update_scripts() {
    log_message "INFO" "Fetching latest scripts from repository..."

    # Download and replace main script
    if curl -fsSL "$SCRIPT_URL" -o "/tmp/ilo4-fan-control.sh"; then
        mv -f "/tmp/ilo4-fan-control.sh" "$INSTALL_DIR/ilo4-fan-control.sh"
        chmod +x "$INSTALL_DIR/ilo4-fan-control.sh"
        log_message "INFO" "Main script updated successfully"
    else
        log_message "ERROR" "Failed to update main script"
        exit 1
    fi

    # Download and replace service file
    if curl -fsSL "$SERVICE_URL" -o "/tmp/ilo4-fan-control.service"; then
        mv -f "/tmp/ilo4-fan-control.service" "$SERVICE_DIR/ilo4-fan-control.service"
        log_message "INFO" "Service file updated successfully"
    else
        log_message "ERROR" "Failed to update service file"
        exit 1
    fi

    # Restart the service
    $SUDO_CMD systemctl restart ilo4-fan-control.service
    log_message "INFO" "Service restarted successfully"
}

# Encapsulate features into functions
initialize_directories() {
    print_color "$BLUE" "Initializing directories..."
    create_directories
}

initialize_files() {
    print_color "$BLUE" "Initializing files..."
    download_and_install_files
}

initialize_configuration() {
    print_color "$BLUE" "Initializing configuration..."
    load_existing_config || configure_settings
    create_configuration_file
}

initialize_service() {
    print_color "$BLUE" "Initializing service..."
    configure_service
}

initialize_dependencies() {
    print_color "$BLUE" "Checking and installing dependencies..."
    install_dependencies
}

run_full_installation() {
    print_color "$CYAN" "Starting full installation..."
    initialize_directories
    initialize_files
    initialize_configuration
    initialize_service
    print_color "$GREEN" "Full installation completed successfully!"
}

run_update() {
    print_color "$CYAN" "Starting update process..."
    initialize_directories
    initialize_files
    initialize_service

    # Ensure configuration values are loaded
    if ! load_existing_config; then
        print_color "$RED" "✗ Failed to load configuration file. Update cannot proceed."
        exit 1
    fi

    # Apply loaded values to variables
    ILO_HOST="$EXISTING_ILO_HOST"
    ILO_USER="$EXISTING_ILO_USER"
    ILO_PASS="$EXISTING_ILO_PASS"
    ENABLE_DYNAMIC_CONTROL="$EXISTING_ENABLE_DYNAMIC_CONTROL"
    LOG_LEVEL="$EXISTING_LOG_LEVEL"
    MONITORING_INTERVAL="$EXISTING_MONITORING_INTERVAL"
    FAN_COUNT="$EXISTING_FAN_COUNT"
    GLOBAL_MIN_SPEED="$EXISTING_GLOBAL_MIN_SPEED"

    # Check for missing required fields
    local missing_vars=()
    [[ -z "$ILO_HOST" ]] && missing_vars+=("ILO_HOST")
    [[ -z "$ILO_USER" ]] && missing_vars+=("ILO_USER")
    [[ -z "$ILO_PASS" ]] && missing_vars+=("ILO_PASS")
    [[ -z "$FAN_COUNT" ]] && missing_vars+=("FAN_COUNT")
    [[ -z "$GLOBAL_MIN_SPEED" ]] && missing_vars+=("GLOBAL_MIN_SPEED")
    [[ -z "$ENABLE_DYNAMIC_CONTROL" ]] && missing_vars+=("ENABLE_DYNAMIC_CONTROL")
    [[ -z "$LOG_LEVEL" ]] && missing_vars+=("LOG_LEVEL")
    [[ -z "$MONITORING_INTERVAL" ]] && missing_vars+=("MONITORING_INTERVAL")
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        print_color "$RED" "✗ The following required config fields are missing: ${missing_vars[*]}"
        print_color "$YELLOW" "Please update your configuration file and try again."
        exit 1
    fi

    print_color "$GREEN" "Update completed successfully!"
}

# Main script execution
main() {
    show_header
    detect_os
    check_prerequisites
    check_privileges
    print_color "$BLUE" "Debug: Argument passed to script: ${1:-}"
    if [[ -z "${1:-}" ]]; then
        print_color "$RED" "No argument provided. Use 'install' or 'update'."
        exit 1
    fi
    case "${1:-}" in
        install|--install)
            run_full_installation
            ;;
        update|--update)
            run_update
            ;;
        *)
            print_color "$RED" "Invalid argument. Use 'install' or 'update'."
            exit 1
            ;;
    esac
    show_completion_message
    exit 0
}

# Redirect output to the log file
exec > >(tee -a /var/log/ilo4-fan-control.log)
exec 2> >(tee -a /var/log/ilo4-fan-control.log >&2)

# Ensure log file exists and is writable
if [[ ! -f /var/log/ilo4-fan-control.log ]]; then
    touch /var/log/ilo4-fan-control.log
    chmod 644 /var/log/ilo4-fan-control.log
fi

# Ensure cleanup of temporary files after downloading templates
if [[ -f "/tmp/ilo4-fan-control.conf.template" ]]; then
    rm -f "/tmp/ilo4-fan-control.conf.template"
fi

# Add detailed feedback for each step
print_color "$BLUE" "Debug: Verifying template cleanup"
if [[ ! -f "/tmp/ilo4-fan-control.conf.template" ]]; then
    print_color "$GREEN" "✓ Temporary template file cleaned up successfully"
else
    print_color "$RED" "✗ Failed to clean up temporary template file"
fi

# Ensure error handling during remote execution
trap 'print_color "$RED" "An unexpected error occurred at line $LINENO during step $STEP. Exiting..."' ERR
set -o errtrace

# Only call main if this script is being run directly (not sourced)
if [[ "$0" == "bash" || "$0" == "-bash" || "$0" == *install.sh ]]; then
    main "$@"
fi

# Ensure all required dependencies are installed
install_dependencies() {
    local deps=(ssh timeout ping grep awk sort tr head sleep)
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        deps+=(sensors)
    fi
    local missing=()
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_color "$YELLOW" "Installing missing dependencies: ${missing[*]}"
        if command -v apt-get &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y "${missing[@]}"
        elif command -v yum &>/dev/null; then
            sudo yum install -y "${missing[@]}"
        else
            print_color "$RED" "No supported package manager found. Please install: ${missing[*]} manually."
            exit 1
        fi
    else
        print_color "$GREEN" "All required dependencies are already installed."
    fi
}

# Stop all running instances of the service before update/install
restart_service_clean() {
    local svc_name="ilo4-fan-control"
    if systemctl list-units --type=service | grep -q "$svc_name"; then
        print_color "$YELLOW" "Stopping all running instances of $svc_name.service..."
        sudo systemctl stop "$svc_name.service"
        sleep 2
        print_color "$YELLOW" "Ensuring no lingering processes..."
        sudo pkill -f ilo4-fan-control.sh || true
    fi
    print_color "$YELLOW" "Starting $svc_name.service..."
    sudo systemctl start "$svc_name.service"
    sudo systemctl enable "$svc_name.service"
}
