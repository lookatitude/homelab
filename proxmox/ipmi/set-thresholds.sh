#!/bin/bash

# IPMI Sensor Threshold Setting Utility for Supermicro Boards
# This script sets sensor thresholds to prevent IPMI from taking over fan control

set -euo pipefail

# Configuration
IPMITOOL_CMD="/usr/bin/ipmitool"
USE_SUDO=true
IPMI_HOST="192.168.1.100"
IPMI_USER="ADMIN"
IPMI_PASS="ADMIN"

# Default thresholds (RPM values)
DEFAULT_LOWER_THRESHOLDS=(0 100 200)          # non-recoverable, critical, non-critical
DEFAULT_UPPER_THRESHOLDS=(1600 1700 1800)     # non-critical, critical, non-recoverable

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

# Auto-detect available fans
detect_fans() {
    local fan_list=()
    
    if sensor_data=$(exec_ipmitool sdr list 2>/dev/null); then
        while IFS= read -r line; do
            if [[ "$line" =~ ^(FAN[0-9A-Z]+)[[:space:]] ]]; then
                fan_list+=("${BASH_REMATCH[1]}")
            fi
        done <<< "$sensor_data"
    fi
    
    printf "%s\n" "${fan_list[@]}"
}

# Show current thresholds for a fan
show_fan_thresholds() {
    local fan_name="$1"
    
    print_info "Current thresholds for $fan_name:"
    if exec_ipmitool sensor get "$fan_name" 2>/dev/null; then
        return 0
    else
        print_error "Failed to get thresholds for $fan_name"
        return 1
    fi
}

# Set thresholds for a specific fan
set_fan_thresholds() {
    local fan_name="$1"
    local lower_nr="${2:-${DEFAULT_LOWER_THRESHOLDS[0]}}"     # non-recoverable
    local lower_cr="${3:-${DEFAULT_LOWER_THRESHOLDS[1]}}"     # critical
    local lower_nc="${4:-${DEFAULT_LOWER_THRESHOLDS[2]}}"     # non-critical
    local upper_nc="${5:-${DEFAULT_UPPER_THRESHOLDS[0]}}"     # non-critical
    local upper_cr="${6:-${DEFAULT_UPPER_THRESHOLDS[1]}}"     # critical
    local upper_nr="${7:-${DEFAULT_UPPER_THRESHOLDS[2]}}"     # non-recoverable
    
    print_info "Setting thresholds for $fan_name..."
    
    # Set lower thresholds
    if exec_ipmitool sensor thresh "$fan_name" lower "$lower_nr" "$lower_cr" "$lower_nc"; then
        print_info "Lower thresholds set: $lower_nr, $lower_cr, $lower_nc"
    else
        print_error "Failed to set lower thresholds for $fan_name"
        return 1
    fi
    
    # Set upper thresholds
    if exec_ipmitool sensor thresh "$fan_name" upper "$upper_nc" "$upper_cr" "$upper_nr"; then
        print_info "Upper thresholds set: $upper_nc, $upper_cr, $upper_nr"
    else
        print_error "Failed to set upper thresholds for $fan_name"
        return 1
    fi
    
    return 0
}

# Set thresholds for all detected fans
set_all_thresholds() {
    local lower_nr="${1:-${DEFAULT_LOWER_THRESHOLDS[0]}}"
    local lower_cr="${2:-${DEFAULT_LOWER_THRESHOLDS[1]}}"
    local lower_nc="${3:-${DEFAULT_LOWER_THRESHOLDS[2]}}"
    local upper_nc="${4:-${DEFAULT_UPPER_THRESHOLDS[0]}}"
    local upper_cr="${5:-${DEFAULT_UPPER_THRESHOLDS[1]}}"
    local upper_nr="${6:-${DEFAULT_UPPER_THRESHOLDS[2]}}"
    
    print_header "Setting Thresholds for All Detected Fans"
    
    local detected_fans
    mapfile -t detected_fans < <(detect_fans)
    
    if [[ ${#detected_fans[@]} -eq 0 ]]; then
        print_error "No fans detected"
        return 1
    fi
    
    print_info "Detected ${#detected_fans[@]} fans: ${detected_fans[*]}"
    echo ""
    
    local success_count=0
    local total_count=${#detected_fans[@]}
    
    for fan in "${detected_fans[@]}"; do
        if set_fan_thresholds "$fan" "$lower_nr" "$lower_cr" "$lower_nc" "$upper_nc" "$upper_cr" "$upper_nr"; then
            ((success_count++))
        fi
        echo ""
    done
    
    print_info "Successfully configured $success_count out of $total_count fans"
    
    if [[ $success_count -eq $total_count ]]; then
        return 0
    else
        return 1
    fi
}

# Show current thresholds for all fans
show_all_thresholds() {
    print_header "Current Fan Sensor Thresholds"
    
    local detected_fans
    mapfile -t detected_fans < <(detect_fans)
    
    if [[ ${#detected_fans[@]} -eq 0 ]]; then
        print_error "No fans detected"
        return 1
    fi
    
    for fan in "${detected_fans[@]}"; do
        echo ""
        show_fan_thresholds "$fan"
    done
}

# Show compact threshold summary
show_threshold_summary() {
    print_header "Fan Sensor Threshold Summary"
    
    if ! exec_ipmitool sensor | grep -E "FAN[0-9A-Z]"; then
        print_error "Failed to get sensor summary"
        return 1
    fi
}

# Interactive threshold configuration
interactive_config() {
    print_header "Interactive Threshold Configuration"
    
    echo "This will help you configure IPMI sensor thresholds for your fans."
    echo "Proper thresholds prevent IPMI from taking over fan control."
    echo ""
    
    # Show detected fans
    local detected_fans
    mapfile -t detected_fans < <(detect_fans)
    
    if [[ ${#detected_fans[@]} -eq 0 ]]; then
        print_error "No fans detected. Cannot continue."
        return 1
    fi
    
    print_info "Detected fans: ${detected_fans[*]}"
    echo ""
    
    # Get fan specifications
    echo "Please provide information about your fans:"
    echo "If unsure, use the defaults (suitable for Noctua NF-F12 PWM fans)"
    echo ""
    
    read -p "Minimum fan RPM when stopped [default: 0]: " min_rpm
    min_rpm=${min_rpm:-0}
    
    read -p "Minimum fan RPM at lowest speed [default: 100]: " min_active_rpm
    min_active_rpm=${min_active_rpm:-100}
    
    read -p "Safe lower threshold RPM [default: 200]: " safe_lower_rpm
    safe_lower_rpm=${safe_lower_rpm:-200}
    
    read -p "Maximum safe RPM [default: 1600]: " max_safe_rpm
    max_safe_rpm=${max_safe_rpm:-1600}
    
    read -p "Critical upper RPM [default: 1700]: " critical_upper_rpm
    critical_upper_rpm=${critical_upper_rpm:-1700}
    
    read -p "Maximum RPM before damage [default: 1800]: " max_rpm
    max_rpm=${max_rpm:-1800}
    
    echo ""
    echo "Summary of thresholds to be set:"
    echo "  Lower Non-Recoverable: $min_rpm RPM"
    echo "  Lower Critical:        $min_active_rpm RPM"
    echo "  Lower Non-Critical:    $safe_lower_rpm RPM"
    echo "  Upper Non-Critical:    $max_safe_rpm RPM"
    echo "  Upper Critical:        $critical_upper_rpm RPM"
    echo "  Upper Non-Recoverable: $max_rpm RPM"
    echo ""
    
    read -p "Apply these thresholds to all fans? [y/N]: " confirm
    
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        set_all_thresholds "$min_rpm" "$min_active_rpm" "$safe_lower_rpm" "$max_safe_rpm" "$critical_upper_rpm" "$max_rpm"
    else
        print_info "Threshold configuration cancelled"
    fi
}

# Preset configurations for common fans
apply_preset() {
    local preset="$1"
    
    case "$preset" in
        "noctua-nf-f12")
            print_info "Applying Noctua NF-F12 PWM preset (300-1500 RPM)"
            set_all_thresholds 0 100 200 1600 1700 1800
            ;;
        "noctua-nf-a14")
            print_info "Applying Noctua NF-A14 PWM preset (300-1500 RPM)"
            set_all_thresholds 0 100 200 1600 1700 1800
            ;;
        "conservative")
            print_info "Applying conservative preset (safe for most fans)"
            set_all_thresholds 0 50 100 2000 2200 2500
            ;;
        "high-speed")
            print_info "Applying high-speed fan preset (for server fans)"
            set_all_thresholds 0 200 400 4000 4500 5000
            ;;
        *)
            print_error "Unknown preset: $preset"
            echo "Available presets:"
            echo "  noctua-nf-f12  - Noctua NF-F12 PWM fans"
            echo "  noctua-nf-a14  - Noctua NF-A14 PWM fans"
            echo "  conservative   - Safe settings for most fans"
            echo "  high-speed     - High-speed server fans"
            return 1
            ;;
    esac
}

# Show usage
show_usage() {
    echo "IPMI Sensor Threshold Setting Utility"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  show                     - Show current thresholds for all fans"
    echo "  show-summary            - Show compact threshold summary"
    echo "  show-fan <fan_name>     - Show thresholds for specific fan"
    echo "  set-all [thresholds]    - Set thresholds for all detected fans"
    echo "  set-fan <fan> [thresh]  - Set thresholds for specific fan"
    echo "  interactive             - Interactive threshold configuration"
    echo "  preset <preset_name>    - Apply preset configuration"
    echo "  detect                  - Detect and list available fans"
    echo ""
    echo "Threshold format (6 values):"
    echo "  <lower_nr> <lower_cr> <lower_nc> <upper_nc> <upper_cr> <upper_nr>"
    echo "  Default: 0 100 200 1600 1700 1800"
    echo ""
    echo "Available presets:"
    echo "  noctua-nf-f12, noctua-nf-a14, conservative, high-speed"
    echo ""
    echo "Examples:"
    echo "  $0 show"
    echo "  $0 set-all"
    echo "  $0 set-all 0 150 250 1500 1600 1700"
    echo "  $0 preset noctua-nf-f12"
    echo "  $0 interactive"
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
        "show")
            show_all_thresholds
            ;;
        "show-summary")
            show_threshold_summary
            ;;
        "show-fan")
            if [[ -z "${2:-}" ]]; then
                print_error "Fan name required. Usage: $0 show-fan <fan_name>"
                exit 1
            fi
            show_fan_thresholds "$2"
            ;;
        "set-all")
            set_all_thresholds "${2:-}" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}"
            ;;
        "set-fan")
            if [[ -z "${2:-}" ]]; then
                print_error "Fan name required. Usage: $0 set-fan <fan_name> [thresholds]"
                exit 1
            fi
            set_fan_thresholds "$2" "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" "${8:-}"
            ;;
        "interactive")
            interactive_config
            ;;
        "preset")
            if [[ -z "${2:-}" ]]; then
                print_error "Preset name required. Usage: $0 preset <preset_name>"
                exit 1
            fi
            apply_preset "$2"
            ;;
        "detect")
            print_header "Detected Fans"
            local detected_fans
            mapfile -t detected_fans < <(detect_fans)
            if [[ ${#detected_fans[@]} -gt 0 ]]; then
                printf "  %s\n" "${detected_fans[@]}"
                echo ""
                print_info "Found ${#detected_fans[@]} fans"
            else
                print_warn "No fans detected"
            fi
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
