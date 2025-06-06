#!/bin/bash

# Manual Fan Control Utility for Supermicro IPMI
# This script provides manual control of fan speeds and IPMI settings

set -euo pipefail

# Configuration
IPMITOOL_CMD="/usr/bin/ipmitool"
USE_SUDO=true
IPMI_HOST="192.168.1.100"
IPMI_USER="ADMIN"
IPMI_PASS="ADMIN"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# Execute ipmitool command
exec_ipmitool() {
    local args=("$@")
    local cmd_args=()
    
    if [[ "$USE_SUDO" == "true" ]] && [[ $EUID -ne 0 ]]; then
        cmd_args+=("sudo")
    fi
    
    cmd_args+=("$IPMITOOL_CMD")
    
    # Add remote parameters if configured
    if [[ -n "$IPMI_USER" ]] && [[ -n "$IPMI_PASS" ]] && [[ -n "$IPMI_HOST" ]]; then
        cmd_args+=("-I" "lanplus" "-U" "$IPMI_USER" "-P" "$IPMI_PASS" "-H" "$IPMI_HOST")
    fi
    
    cmd_args+=("${args[@]}")
    
    if ! timeout 30 "${cmd_args[@]}" 2>/dev/null; then
        print_error "IPMI command failed: ${cmd_args[*]}"
        return 1
    fi
    return 0
}

# Get current IPMI fan mode
get_fan_mode() {
    local mode_num
    if mode_num=$(exec_ipmitool raw 0x30 0x45 0x00 2>/dev/null); then
        case "$mode_num" in
            "00") echo "STANDARD" ;;
            "01") echo "FULL" ;;
            "02") echo "OPTIMAL" ;;
            "03") echo "PUE" ;;
            "04") echo "HEAVY_IO" ;;
            *) echo "UNKNOWN($mode_num)" ;;
        esac
    else
        echo "ERROR"
    fi
}

# Set IPMI fan mode
set_fan_mode() {
    local mode="$1"
    local mode_num
    
    case "$mode" in
        "STANDARD"|"0") mode_num="0x00"; mode="STANDARD" ;;
        "FULL"|"1") mode_num="0x01"; mode="FULL" ;;
        "OPTIMAL"|"2") mode_num="0x02"; mode="OPTIMAL" ;;
        "PUE"|"3") mode_num="0x03"; mode="PUE" ;;
        "HEAVY_IO"|"4") mode_num="0x04"; mode="HEAVY_IO" ;;
        *) print_error "Invalid fan mode: $mode"; return 1 ;;
    esac
    
    print_info "Setting IPMI fan mode to $mode"
    if exec_ipmitool raw 0x30 0x45 0x01 "$mode_num"; then
        sleep 5
        print_info "Fan mode set to $mode successfully"
        return 0
    else
        print_error "Failed to set fan mode to $mode"
        return 1
    fi
}

# Get fan level for zone
get_fan_level() {
    local zone="$1"
    local zone_hex
    zone_hex=$(printf "0x%02x" "$zone")
    
    local result
    if result=$(exec_ipmitool raw 0x30 0x70 0x66 0x00 "$zone_hex" 2>/dev/null); then
        printf "%d" "$result" 2>/dev/null || echo "0"
    else
        echo "ERROR"
    fi
}

# Set fan level for zone
set_fan_level() {
    local zone="$1"
    local level="$2"
    
    if [[ ! "$zone" =~ ^[0-9]+$ ]] || (( zone < 0 || zone > 100 )); then
        print_error "Invalid zone: $zone"
        return 1
    fi
    
    if [[ ! "$level" =~ ^[0-9]+$ ]] || (( level < 0 || level > 100 )); then
        print_error "Invalid fan level: $level"
        return 1
    fi
    
    local zone_hex
    local level_hex
    zone_hex=$(printf "0x%02x" "$zone")
    level_hex=$(printf "0x%02x" "$level")
    
    print_info "Setting zone $zone fan level to $level%"
    if exec_ipmitool raw 0x30 0x70 0x66 0x01 "$zone_hex" "$level_hex"; then
        sleep 2
        print_info "Zone $zone fan level set to $level% successfully"
        return 0
    else
        print_error "Failed to set zone $zone fan level to $level%"
        return 1
    fi
}

# Show current status
show_status() {
    print_header "Current IPMI Fan Status"
    
    # Show fan mode
    local current_mode
    current_mode=$(get_fan_mode)
    echo "IPMI Fan Mode: $current_mode"
    echo ""
    
    # Show zone levels
    echo "Zone Levels:"
    local cpu_level
    local hd_level
    cpu_level=$(get_fan_level 0)
    hd_level=$(get_fan_level 1)
    echo "  CPU Zone (0): ${cpu_level}%"
    echo "  HD Zone (1):  ${hd_level}%"
    echo ""
    
    # Show fan sensors
    echo "Fan Sensor Information:"
    if sensor_data=$(exec_ipmitool sdr list 2>/dev/null); then
        echo "$sensor_data" | grep -E "FAN[0-9A-Z]" | while IFS= read -r line; do
            echo "  $line"
        done
    else
        print_error "Failed to read sensor data"
    fi
}

# Interactive mode
interactive_mode() {
    while true; do
        print_header "Supermicro Fan Control - Interactive Mode"
        echo "1) Show current status"
        echo "2) Set fan mode"
        echo "3) Set CPU zone (0) fan level"
        echo "4) Set HD zone (1) fan level"
        echo "5) Set both zones to same level"
        echo "6) Reset to safe levels (100%)"
        echo "7) Show fan sensor details"
        echo "8) Exit"
        echo ""
        read -p "Select option [1-8]: " choice
        
        case $choice in
            1)
                show_status
                ;;
            2)
                echo ""
                echo "Available fan modes:"
                echo "0 - STANDARD"
                echo "1 - FULL"
                echo "2 - OPTIMAL"
                echo "3 - PUE"
                echo "4 - HEAVY_IO"
                read -p "Enter mode [0-4]: " mode
                set_fan_mode "$mode"
                ;;
            3)
                read -p "Enter CPU zone fan level [0-100]: " level
                set_fan_level 0 "$level"
                ;;
            4)
                read -p "Enter HD zone fan level [0-100]: " level
                set_fan_level 1 "$level"
                ;;
            5)
                read -p "Enter fan level for both zones [0-100]: " level
                set_fan_level 0 "$level"
                set_fan_level 1 "$level"
                ;;
            6)
                print_info "Resetting all zones to 100% (safe level)"
                set_fan_level 0 100
                set_fan_level 1 100
                ;;
            7)
                print_header "Detailed Fan Sensor Information"
                if exec_ipmitool sensor | grep -E "FAN[0-9A-Z]"; then
                    echo ""
                else
                    print_error "Failed to read detailed sensor data"
                fi
                ;;
            8)
                print_info "Exiting interactive mode"
                break
                ;;
            *)
                print_error "Invalid option. Please select 1-8."
                ;;
        esac
        
        echo ""
        read -p "Press Enter to continue..."
    done
}

# Show usage
show_usage() {
    echo "Supermicro Manual Fan Control Utility"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  status                    - Show current fan status"
    echo "  interactive              - Enter interactive mode"
    echo "  set-mode <mode>          - Set fan mode (STANDARD/FULL/OPTIMAL/PUE/HEAVY_IO)"
    echo "  set-level <zone> <level> - Set fan level for zone (0=CPU, 1=HD)"
    echo "  reset                    - Reset all zones to safe levels (100%)"
    echo ""
    echo "Examples:"
    echo "  $0 status"
    echo "  $0 set-mode FULL"
    echo "  $0 set-level 0 50"
    echo "  $0 set-level 1 30"
    echo "  $0 reset"
    echo ""
}

# Main execution
main() {
    # Check if ipmitool is available
    if ! command -v "$IPMITOOL_CMD" >/dev/null 2>&1; then
        print_error "ipmitool not found at $IPMITOOL_CMD"
        exit 1
    fi
    
    # Test IPMI connectivity
    if ! exec_ipmitool sdr list >/dev/null 2>&1; then
        print_error "Failed to connect to IPMI. Check configuration and permissions."
        exit 1
    fi
    
    case "${1:-interactive}" in
        "status")
            show_status
            ;;
        "interactive")
            interactive_mode
            ;;
        "set-mode")
            if [[ -z "${2:-}" ]]; then
                print_error "Mode required. Usage: $0 set-mode <mode>"
                exit 1
            fi
            set_fan_mode "$2"
            ;;
        "set-level")
            if [[ -z "${2:-}" ]] || [[ -z "${3:-}" ]]; then
                print_error "Zone and level required. Usage: $0 set-level <zone> <level>"
                exit 1
            fi
            set_fan_level "$2" "$3"
            ;;
        "reset")
            print_info "Resetting all zones to safe levels (100%)"
            set_fan_level 0 100
            set_fan_level 1 100
            ;;
        "help"|"--help"|"-h")
            show_usage
            ;;
        *)
            print_error "Unknown command: ${1:-}"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"
