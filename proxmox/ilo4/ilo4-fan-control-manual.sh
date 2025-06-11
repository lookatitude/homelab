#!/bin/bash

# HP iLO4 Manual Fan Control Script
# Provides manual control capabilities for iLO4 fan management
# Usage: ./ilo4-fan-control-manual.sh [options]

set -euo pipefail

# === CONFIGURATION ===
ILO_HOST="192.168.1.100"      # iLO IP or hostname
ILO_USER="Administrator"       # iLO username
ILO_PASS="password"           # iLO password

USE_SSH_PASS=true             # Set to false to use SSH key auth
FAN_COUNT=6                   # Number of fans (fan 0 to FAN_COUNT-1)
GLOBAL_MIN_SPEED=60          # Minimum fan speed
PID_MIN_LOW=1600             # Minimum low for all PIDs
# ========================

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_color() {
    local color=$1
    shift
    echo -e "${color}$*${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
HP iLO4 Manual Fan Control Script v1.0.0

DESCRIPTION:
  Manual control interface for HP iLO4 fan management. This script provides
  both interactive and command-line access to fan control functions.

USAGE:
  $(basename "$0") [OPTIONS]

OPTIONS:
  --interactive, -i          Interactive mode with menu interface
  --status, -s              Show current fan status and temperatures
  --set-speed FAN SPEED     Set specific fan speed (0-255)
  --set-all SPEED          Set all fans to the same speed
  --reset                  Reset fans to safe defaults (speed 60)
  --test                   Test iLO connection and basic functionality
  --emergency              Set all fans to maximum speed (255)
  --quiet                  Quiet mode - minimal output
  --help, -h               Show this help message

EXAMPLES:
  # Interactive menu mode
  $(basename "$0") --interactive

  # Check current status
  $(basename "$0") --status

  # Set fan 3 to speed 128 (50% power)
  $(basename "$0") --set-speed 3 128

  # Set all fans to quiet operation (speed 80)
  $(basename "$0") --set-all 80

  # Reset all fans to safe defaults
  $(basename "$0") --reset

  # Emergency cooling mode
  $(basename "$0") --emergency

  # Test iLO connectivity
  $(basename "$0") --test

CONFIGURATION:
  Edit the configuration section at the top of this script to set:
  - ILO_HOST: iLO IP address or hostname
  - ILO_USER: iLO username  
  - ILO_PASS: iLO password
  - FAN_COUNT: Number of fans in your system (typically 6)

SAFETY NOTES:
  - Minimum fan speed is automatically enforced (typically 60)
  - Emergency mode sets all fans to maximum for critical cooling
  - Always test configuration changes in a safe environment
  - Monitor system temperatures when making manual adjustments

FAN SPEED REFERENCE:
  0-50:   Very quiet (may cause overheating)
  51-100: Quiet operation (suitable for idle/low load)
  101-150: Moderate cooling (normal operation)
  151-200: High cooling (heavy workloads)
  201-255: Maximum cooling (emergency/stress testing)

For automatic temperature-based control, use the main fan control service:
  sudo systemctl start ilo4-fan-control

EOF
}

# Build SSH command options (safe legacy ciphers for iLO4)
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=15
    -o ServerAliveInterval=10
    -o ServerAliveCountMax=3
    -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
    -o HostKeyAlgorithms=+ssh-rsa,ssh-dss
    -o PubkeyAcceptedAlgorithms=+ssh-rsa,ssh-dss
)

# Build the SSH command
if [ "$USE_SSH_PASS" = true ]; then
    if ! command -v sshpass &>/dev/null; then
        print_color "$RED" "ERROR: sshpass is not installed!"
        print_color "$YELLOW" "Install with: sudo apt install sshpass"
        exit 1
    fi
    SSH_EXEC=(sshpass -p "$ILO_PASS" ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
else
    SSH_EXEC=(ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
fi

# Function to execute a command on iLO
execute_ilo_command() {
    local cmd="$1"
    local silent="${2:-false}"
    
    if [[ "$silent" != "true" ]]; then
        print_color "$BLUE" "Executing: $cmd"
    fi
    
    if timeout 30 "${SSH_EXEC[@]}" "$cmd" 2>&1; then
        if [[ "$silent" != "true" ]]; then
            print_color "$GREEN" "✓ Success"
        fi
        return 0
    else
        if [[ "$silent" != "true" ]]; then
            print_color "$RED" "✗ Failed: $cmd"
        fi
        return 1
    fi
}

# Function to test iLO connection
test_connection() {
    print_color "$YELLOW" "Testing iLO connection..."
    
    if ! ping -c 1 -W 3 "$ILO_HOST" >/dev/null 2>&1; then
        print_color "$RED" "✗ Cannot ping iLO host: $ILO_HOST"
        return 1
    fi
    
    if execute_ilo_command "version" "true"; then
        print_color "$GREEN" "✓ iLO connection successful"
        return 0
    else
        print_color "$RED" "✗ iLO SSH connection failed"
        return 1
    fi
}

# Function to get fan status
show_fan_status() {
    print_color "$YELLOW" "Getting fan status from iLO..."
    
    if ! test_connection; then
        print_color "$RED" "Cannot connect to iLO. Check configuration."
        return 1
    fi
    
    print_color "$BLUE" "Fan Information:"
    execute_ilo_command "fan info"
    
    echo
    print_color "$BLUE" "Fan PWM Settings:"
    for ((i=0; i < FAN_COUNT; i++)); do
        echo -n "Fan $i: "
        execute_ilo_command "fan p $i show" "true" | grep -o '[0-9]\+%' || echo "Unknown"
    done
}

# Function to show all fan info (fan info a)
show_fan_info_a() {
    print_color "$YELLOW" "Getting ALL fan info from iLO (fan info a)..."
    if ! test_connection; then
        print_color "$RED" "Cannot connect to iLO. Check configuration."
        return 1
    fi
    print_color "$BLUE" "fan info a output:"
    execute_ilo_command "fan info a"
}

# Function to set specific fan speed
set_fan_speed() {
    local fan=$1
    local speed=$2
    
    if [[ ! "$fan" =~ ^[0-9]+$ ]] || [[ $fan -ge $FAN_COUNT ]] || [[ $fan -lt 0 ]]; then
        print_color "$RED" "Invalid fan number: $fan (valid range: 0-$((FAN_COUNT-1)))"
        return 1
    fi
    
    if [[ ! "$speed" =~ ^[0-9]+$ ]] || [[ $speed -gt 255 ]] || [[ $speed -lt 0 ]]; then
        print_color "$RED" "Invalid speed: $speed (valid range: 0-255)"
        return 1
    fi
    
    print_color "$YELLOW" "Setting fan $fan to speed $speed..."
    if execute_ilo_command "fan p $fan max $speed"; then
        print_color "$GREEN" "✓ Fan $fan set to speed $speed"
    else
        print_color "$RED" "✗ Failed to set fan $fan speed"
        return 1
    fi
}

# Function to set all fans to the same speed
set_all_fans() {
    local speed=$1
    
    if [[ ! "$speed" =~ ^[0-9]+$ ]] || [[ $speed -gt 255 ]] || [[ $speed -lt 0 ]]; then
        print_color "$RED" "Invalid speed: $speed (valid range: 0-255)"
        return 1
    fi
    
    print_color "$YELLOW" "Setting all fans to speed $speed..."
    
    for ((i=0; i < FAN_COUNT; i++)); do
        if execute_ilo_command "fan p $i max $speed"; then
            print_color "$GREEN" "✓ Fan $i set to speed $speed"
        else
            print_color "$RED" "✗ Failed to set fan $i speed"
        fi
        sleep 0.5
    done
}

# Function to reset fans to safe defaults
reset_fans() {
    print_color "$YELLOW" "Resetting fans to safe defaults..."
    
    if ! test_connection; then
        print_color "$RED" "Cannot connect to iLO. Check configuration."
        return 1
    fi
    
    # Set minimum speeds
    for ((i=0; i < FAN_COUNT; i++)); do
        execute_ilo_command "fan p $i min $GLOBAL_MIN_SPEED"
        sleep 0.5
    done
    
    # Set moderate maximum speeds
    for ((i=0; i < FAN_COUNT; i++)); do
        execute_ilo_command "fan p $i max 100"
        sleep 0.5
    done
    
    print_color "$GREEN" "✓ Fans reset to safe defaults"
}

# Function to set emergency cooling
emergency_cooling() {
    print_color "$RED" "EMERGENCY COOLING: Setting all fans to maximum speed!"
    
    if ! test_connection; then
        print_color "$RED" "Cannot connect to iLO. Check configuration."
        return 1
    fi
    
    for ((i=0; i < FAN_COUNT; i++)); do
        execute_ilo_command "fan p $i max 255"
        sleep 0.2
    done
    
    print_color "$GREEN" "✓ All fans set to maximum speed"
}

# Interactive mode function
interactive_mode() {
    while true; do
        echo
        print_color "$BLUE" "=== HP iLO4 Fan Control - Interactive Mode ==="
        echo "1. Show fan status"
        echo "2. Set specific fan speed"
        echo "3. Set all fans to same speed"
        echo "4. Reset fans to safe defaults"
        echo "5. Emergency cooling (max speed)"
        echo "6. Test iLO connection"
        echo "7. Show all fan info (fan info a)"
        echo "0. Exit"
        echo
        read -p "Select option [0-7]: " choice
        
        case $choice in
            1)
                show_fan_status
                ;;
            2)
                read -p "Enter fan number (0-$((FAN_COUNT-1))): " fan
                read -p "Enter speed (0-255): " speed
                set_fan_speed "$fan" "$speed"
                ;;
            3)
                read -p "Enter speed for all fans (0-255): " speed
                set_all_fans "$speed"
                ;;
            4)
                read -p "Reset all fans to safe defaults? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    reset_fans
                fi
                ;;
            5)
                read -p "Set emergency cooling (MAX SPEED)? (y/N): " confirm
                if [[ $confirm =~ ^[Yy]$ ]]; then
                    emergency_cooling
                fi
                ;;
            6)
                test_connection
                ;;
            7)
                show_fan_info_a
                ;;
            0)
                print_color "$GREEN" "Goodbye!"
                exit 0
                ;;
            *)
                print_color "$RED" "Invalid option. Please try again."
                ;;
        esac
        
        echo
        read -p "Press Enter to continue..."
    done
}

# Main script logic
main() {
    # Check if running as root/sudo
    if [[ $EUID -ne 0 ]]; then
        print_color "$YELLOW" "This script should be run as root or with sudo for best results."
    fi
    
    # Parse command line arguments
    case "${1:-}" in
        --interactive|-i)
            interactive_mode
            ;;
        --status|-s)
            show_fan_status
            ;;
        --set-speed)
            if [[ $# -ne 3 ]]; then
                print_color "$RED" "Usage: $0 --set-speed FAN SPEED"
                exit 1
            fi
            set_fan_speed "$2" "$3"
            ;;
        --set-all)
            if [[ $# -ne 2 ]]; then
                print_color "$RED" "Usage: $0 --set-all SPEED"
                exit 1
            fi
            set_all_fans "$2"
            ;;
        --reset)
            reset_fans
            ;;
        --test)
            test_connection
            ;;
        --emergency)
            emergency_cooling
            ;;
        --fan-info-a)
            show_fan_info_a
            ;;
        --help|-h|"")
            show_usage
            ;;
        *)
            print_color "$RED" "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
