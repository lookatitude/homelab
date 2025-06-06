#!/bin/bash

# iLO4 Threshold Management Script
# Provides utilities for managing fan control thresholds and advanced settings

set -euo pipefail

# Script info
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="iLO4 Threshold Manager"

# Default configuration file path
CONFIG_FILE="/etc/ilo4-fan-control/ilo4-fan-control.conf"
LOCAL_CONFIG_FILE="./ilo4-fan-control.conf"

# Use local config if it exists and system config doesn't
if [[ -f "$LOCAL_CONFIG_FILE" && ! -f "$CONFIG_FILE" ]]; then
    CONFIG_FILE="$LOCAL_CONFIG_FILE"
fi

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

# Function to show usage
show_usage() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION

USAGE:
  $(basename "$0") [OPTIONS]

OPTIONS:
  --show-thresholds, -s         Show current temperature thresholds
  --set-threshold TEMP SPEED    Set temperature threshold (°C) and fan speed (0-255)
  --add-temp-step TEMP SPEED    Add a new custom temperature step
  --remove-temp-step TEMP       Remove a temperature step
  --list-temp-steps            List all configured temperature steps
  --reset-thresholds           Reset to default temperature thresholds
  --show-config                Show current configuration
  --backup-config              Backup current configuration
  --restore-config FILE        Restore configuration from backup
  --validate-config            Validate current configuration
  --test-connection            Test iLO connection
  --emergency-reset            Reset all fans to safe emergency speeds
  --help, -h                   Show this help message

EXAMPLES:
  $(basename "$0") --show-thresholds
  $(basename "$0") --set-threshold 65 100
  $(basename "$0") --add-temp-step 75 180
  $(basename "$0") --remove-temp-step 75
  $(basename "$0") --list-temp-steps
  $(basename "$0") --test-connection
  $(basename "$0") --emergency-reset

NOTES:
  - Most operations require root privileges
  - Configuration changes require service restart to take effect
  - Always backup configuration before making changes
  - Temperature steps can be customized to fit your cooling needs

EOF
}

# Function to load configuration
load_config() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_color "$RED" "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    source "$CONFIG_FILE"
    return 0
}

# Function to show current thresholds
show_thresholds() {
    print_color "$CYAN" "Current Temperature Thresholds:"
    print_color "$CYAN" "================================"
    
    if ! load_config; then
        return 1
    fi
    
    print_color "$YELLOW" "Current Temperature Thresholds:"
    echo ""
    
    # Load and display current temperature steps dynamically
    source "$CONFIG_FILE" 2>/dev/null || {
        print_color "$RED" "Error: Could not load configuration file: $CONFIG_FILE"
        return 1
    }
    
    # Display thresholds based on TEMP_STEPS array
    if [[ -n "${TEMP_STEPS[*]}" ]]; then
        local sorted_steps=($(printf '%s\n' "${TEMP_STEPS[@]}" | sort -nr))
        local prev_temp=999
        
        for step in "${sorted_steps[@]}"; do
            local threshold_var="TEMP_THRESHOLD_${step}"
            local speed="${!threshold_var:-"Not set"}"
            
            if [[ $prev_temp == 999 ]]; then
                print_color "$YELLOW" "Emergency (≥${step}°C):      $speed"
            else
                print_color "$YELLOW" "Range (${step}-$((prev_temp-1))°C):    $speed"
            fi
            prev_temp=$step
        done
        
        # Show default threshold
        print_color "$YELLOW" "Default (<${TEMP_STEPS[-1]}°C):        ${TEMP_THRESHOLD_DEFAULT:-50}"
    else
        print_color "$RED" "No temperature steps defined in configuration"
        return 1
    fi
    echo ""
    print_color "$BLUE" "Maximum CPU Temperature: ${MAX_TEMP_CPU:-80}°C"
    print_color "$BLUE" "Emergency Fan Speed:     ${EMERGENCY_SPEED:-255}"
}

# Function to set a temperature threshold
set_threshold() {
    local temp="$1"
    local speed="$2"
    
    # Validate inputs
    if ! [[ "$temp" =~ ^[0-9]+$ ]] || [[ $temp -lt 30 ]] || [[ $temp -gt 100 ]]; then
        print_color "$RED" "Invalid temperature. Must be between 30 and 100°C"
        return 1
    fi
    
    if ! [[ "$speed" =~ ^[0-9]+$ ]] || [[ $speed -lt 0 ]] || [[ $speed -gt 255 ]]; then
        print_color "$RED" "Invalid fan speed. Must be between 0 and 255"
        return 1
    fi
    
    if ! load_config; then
        return 1
    fi
    
    # Backup current config
    backup_config_internal
    
    # Dynamically determine which threshold to update based on TEMP_STEPS
    source "$CONFIG_FILE" 2>/dev/null
    local threshold_var="TEMP_THRESHOLD_DEFAULT"  # Default fallback
    
    if [[ -n "${TEMP_STEPS[*]}" ]]; then
        local sorted_steps=($(printf '%s\n' "${TEMP_STEPS[@]}" | sort -nr))
        
        # Find the appropriate threshold variable
        for step in "${sorted_steps[@]}"; do
            if [[ $temp -ge $step ]]; then
                threshold_var="TEMP_THRESHOLD_${step}"
                break
            fi
        done
    fi
    
    # Check if the threshold variable exists in config, if not add it
    if ! grep -q "^${threshold_var}=" "$CONFIG_FILE"; then
        echo "${threshold_var}=${speed}" >> "$CONFIG_FILE"
        print_color "$YELLOW" "Added new threshold: ${threshold_var}=${speed}"
    else
        # Update the configuration file
        sed -i "s/^${threshold_var}=.*/${threshold_var}=${speed}/" "$CONFIG_FILE"
    fi
    
    print_color "$GREEN" "✓ Updated ${threshold_var} to ${speed} (for ${temp}°C)"
    print_color "$YELLOW" "⚠ Restart the service to apply changes: sudo systemctl restart ilo4-fan-control"
}

# Function to reset thresholds to defaults
reset_thresholds() {
    if ! load_config; then
        return 1
    fi
    
    print_color "$YELLOW" "Resetting temperature thresholds to defaults..."
    
    # Backup current config
    backup_config_internal
    
    # Load current config to get TEMP_STEPS
    source "$CONFIG_FILE" 2>/dev/null
    
    # Reset to default values based on current TEMP_STEPS
    if [[ -n "${TEMP_STEPS[*]}" ]]; then
        # Reset default temperature steps and their values
        sed -i 's/^TEMP_STEPS=.*/TEMP_STEPS=(90 80 70 60 50)/' "$CONFIG_FILE"
        sed -i 's/^TEMP_THRESHOLD_90=.*/TEMP_THRESHOLD_90=255/' "$CONFIG_FILE"
        sed -i 's/^TEMP_THRESHOLD_80=.*/TEMP_THRESHOLD_80=200/' "$CONFIG_FILE"
        sed -i 's/^TEMP_THRESHOLD_70=.*/TEMP_THRESHOLD_70=150/' "$CONFIG_FILE"
        sed -i 's/^TEMP_THRESHOLD_60=.*/TEMP_THRESHOLD_60=100/' "$CONFIG_FILE"
        sed -i 's/^TEMP_THRESHOLD_50=.*/TEMP_THRESHOLD_50=75/' "$CONFIG_FILE"
    else
        # Add default configuration if missing
        echo "TEMP_STEPS=(90 80 70 60 50)" >> "$CONFIG_FILE"
        echo "TEMP_THRESHOLD_90=255" >> "$CONFIG_FILE"
        echo "TEMP_THRESHOLD_80=200" >> "$CONFIG_FILE"
        echo "TEMP_THRESHOLD_70=150" >> "$CONFIG_FILE"
        echo "TEMP_THRESHOLD_60=100" >> "$CONFIG_FILE"
        echo "TEMP_THRESHOLD_50=75" >> "$CONFIG_FILE"
    fi
    
    sed -i 's/^TEMP_THRESHOLD_DEFAULT=.*/TEMP_THRESHOLD_DEFAULT=50/' "$CONFIG_FILE"
    
    print_color "$GREEN" "✓ Temperature thresholds reset to defaults"
    print_color "$YELLOW" "⚠ Restart the service to apply changes: sudo systemctl restart ilo4-fan-control"
}

# Function to show full configuration
show_config() {
    print_color "$CYAN" "Current iLO4 Fan Control Configuration:"
    print_color "$CYAN" "======================================"
    
    if ! load_config; then
        return 1
    fi
    
    print_color "$YELLOW" "Connection Settings:"
    print_color "$GREEN" "  iLO Host:           ${ILO_HOST:-<not set>}"
    print_color "$GREEN" "  iLO User:           ${ILO_USER:-<not set>}"
    print_color "$GREEN" "  SSH Password Auth:  ${USE_SSH_PASS:-true}"
    echo ""
    
    print_color "$YELLOW" "Fan Settings:"
    print_color "$GREEN" "  Fan Count:          ${FAN_COUNT:-6}"
    print_color "$GREEN" "  Minimum Speed:      ${GLOBAL_MIN_SPEED:-60}"
    print_color "$GREEN" "  PID Minimum Low:    ${PID_MIN_LOW:-1600}"
    echo ""
    
    print_color "$YELLOW" "Control Settings:"
    print_color "$GREEN" "  Dynamic Control:    ${ENABLE_DYNAMIC_CONTROL:-true}"
    print_color "$GREEN" "  Monitor Interval:   ${MONITORING_INTERVAL:-30}s"
    print_color "$GREEN" "  Max CPU Temp:       ${MAX_TEMP_CPU:-80}°C"
    echo ""
    
    print_color "$YELLOW" "Logging:"
    print_color "$GREEN" "  Log Level:          ${LOG_LEVEL:-INFO}"
    print_color "$GREEN" "  Log File:           ${LOG_FILE:-/var/log/ilo4-fan-control.log}"
    echo ""
    
    show_thresholds
}

# Function to backup configuration
backup_config_internal() {
    local backup_file="/etc/ilo4-fan-control/ilo4-fan-control.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    print_color "$BLUE" "Configuration backed up to: $backup_file"
}

# Function to backup configuration (user-called)
backup_config() {
    local backup_file="ilo4-fan-control.conf.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$CONFIG_FILE" "$backup_file"
    print_color "$GREEN" "✓ Configuration backed up to: $backup_file"
}

# Function to restore configuration
restore_config() {
    local backup_file="$1"
    
    if [[ ! -f "$backup_file" ]]; then
        print_color "$RED" "Backup file not found: $backup_file"
        return 1
    fi
    
    # Validate the backup file
    if ! bash -n "$backup_file"; then
        print_color "$RED" "Invalid backup file (syntax errors)"
        return 1
    fi
    
    # Create a backup of current config before restoring
    backup_config_internal
    
    # Restore the configuration
    cp "$backup_file" "$CONFIG_FILE"
    print_color "$GREEN" "✓ Configuration restored from: $backup_file"
    print_color "$YELLOW" "⚠ Restart the service to apply changes: sudo systemctl restart ilo4-fan-control"
}

# Function to validate configuration
validate_config() {
    print_color "$BLUE" "Validating configuration..."
    
    if ! load_config; then
        return 1
    fi
    
    local errors=0
    
    # Check required settings
    if [[ "${ILO_HOST:-}" == "<ip>" ]] || [[ -z "${ILO_HOST:-}" ]]; then
        print_color "$RED" "✗ ILO_HOST must be configured"
        ((errors++))
    fi
    
    if [[ "${ILO_USER:-}" == "<username>" ]] || [[ -z "${ILO_USER:-}" ]]; then
        print_color "$RED" "✗ ILO_USER must be configured"
        ((errors++))
    fi
    
    if [[ "${USE_SSH_PASS:-}" == "true" ]] && [[ "${ILO_PASS:-}" == "<password>" ]]; then
        print_color "$RED" "✗ ILO_PASS must be configured when using password authentication"
        ((errors++))
    fi
    
    # Validate numeric ranges
    if ! [[ "${FAN_COUNT:-6}" =~ ^[0-9]+$ ]] || [[ ${FAN_COUNT:-6} -lt 1 ]] || [[ ${FAN_COUNT:-6} -gt 20 ]]; then
        print_color "$RED" "✗ FAN_COUNT must be between 1 and 20"
        ((errors++))
    fi
    
    if ! [[ "${GLOBAL_MIN_SPEED:-60}" =~ ^[0-9]+$ ]] || [[ ${GLOBAL_MIN_SPEED:-60} -lt 0 ]] || [[ ${GLOBAL_MIN_SPEED:-60} -gt 255 ]]; then
        print_color "$RED" "✗ GLOBAL_MIN_SPEED must be between 0 and 255"
        ((errors++))
    fi
    
    # Validate temperature thresholds
    local thresholds=("TEMP_THRESHOLD_67" "TEMP_THRESHOLD_58" "TEMP_THRESHOLD_54" "TEMP_THRESHOLD_52" "TEMP_THRESHOLD_50" "TEMP_THRESHOLD_DEFAULT")
    for threshold in "${thresholds[@]}"; do
        local value="${!threshold:-}"
        if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ $value -lt 0 ]] || [[ $value -gt 255 ]]; then
            print_color "$RED" "✗ $threshold must be between 0 and 255"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        print_color "$GREEN" "✓ Configuration validation passed"
        return 0
    else
        print_color "$RED" "✗ Configuration validation failed with $errors errors"
        return 1
    fi
}

# Function to test connection
test_connection() {
    print_color "$BLUE" "Testing iLO connection..."
    
    if ! load_config; then
        return 1
    fi
    
    # Build SSH command
    local ssh_opts=(
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ConnectTimeout=10
    )
    
    if [[ "${USE_SSH_PASS:-true}" == "true" ]]; then
        if ! command -v sshpass &>/dev/null; then
            print_color "$RED" "✗ sshpass not installed"
            return 1
        fi
        
        if timeout 15 sshpass -p "${ILO_PASS:-}" ssh "${ssh_opts[@]}" "${ILO_USER:-}@${ILO_HOST:-}" "version" &>/dev/null; then
            print_color "$GREEN" "✓ SSH connection successful"
            return 0
        else
            print_color "$RED" "✗ SSH connection failed"
            return 1
        fi
    else
        if timeout 15 ssh "${ssh_opts[@]}" "${ILO_USER:-}@${ILO_HOST:-}" "version" &>/dev/null; then
            print_color "$GREEN" "✓ SSH connection successful"
            return 0
        else
            print_color "$RED" "✗ SSH connection failed"
            return 1
        fi
    fi
}

# Function to perform emergency reset
emergency_reset() {
    print_color "$YELLOW" "⚠ EMERGENCY RESET: Setting all fans to maximum speed"
    
    if ! load_config; then
        return 1
    fi
    
    # Build SSH command
    local ssh_opts=(
        -o StrictHostKeyChecking=no
        -o UserKnownHostsFile=/dev/null
        -o LogLevel=ERROR
        -o ConnectTimeout=10
    )
    
    local ssh_cmd=()
    if [[ "${USE_SSH_PASS:-true}" == "true" ]]; then
        if ! command -v sshpass &>/dev/null; then
            print_color "$RED" "✗ sshpass not installed"
            return 1
        fi
        ssh_cmd=(sshpass -p "${ILO_PASS:-}" ssh "${ssh_opts[@]}" "${ILO_USER:-}@${ILO_HOST:-}")
    else
        ssh_cmd=(ssh "${ssh_opts[@]}" "${ILO_USER:-}@${ILO_HOST:-}")
    fi
    
    # Set all fans to maximum speed
    local fan_count="${FAN_COUNT:-6}"
    local emergency_speed="${EMERGENCY_SPEED:-255}"
    
    print_color "$YELLOW" "Setting $fan_count fans to speed $emergency_speed..."
    
    for ((i=0; i < fan_count; i++)); do
        if timeout 15 "${ssh_cmd[@]}" "fan p $i max $emergency_speed" &>/dev/null; then
            print_color "$GREEN" "✓ Fan $i set to emergency speed"
        else
            print_color "$RED" "✗ Failed to set Fan $i"
        fi
    done
    
    print_color "$YELLOW" "Emergency reset completed"
}

# Function to add a custom temperature step
add_temp_step() {
    local temp="$1"
    local speed="$2"
    
    # Validate inputs
    if ! [[ "$temp" =~ ^[0-9]+$ ]] || [[ $temp -lt 30 ]] || [[ $temp -gt 100 ]]; then
        print_color "$RED" "Invalid temperature. Must be between 30 and 100°C"
        return 1
    fi
    
    if ! [[ "$speed" =~ ^[0-9]+$ ]] || [[ $speed -lt 0 ]] || [[ $speed -gt 255 ]]; then
        print_color "$RED" "Invalid fan speed. Must be between 0 and 255"
        return 1
    fi
    
    if ! load_config; then
        return 1
    fi
    
    # Backup current config
    backup_config_internal
    
    # Load current configuration
    source "$CONFIG_FILE" 2>/dev/null
    
    # Check if temperature step already exists
    local temp_exists=false
    for step in "${TEMP_STEPS[@]}"; do
        if [[ $step -eq $temp ]]; then
            temp_exists=true
            break
        fi
    done
    
    if [[ $temp_exists == true ]]; then
        print_color "$YELLOW" "Temperature step ${temp}°C already exists. Updating fan speed..."
        sed -i "s/^TEMP_THRESHOLD_${temp}=.*/TEMP_THRESHOLD_${temp}=${speed}/" "$CONFIG_FILE"
    else
        # Add new temperature step to TEMP_STEPS array
        local new_steps=(${TEMP_STEPS[@]} $temp)
        # Sort the array in descending order
        IFS=$'\n' new_steps=($(sort -nr <<<"${new_steps[*]}"))
        unset IFS
        
        # Update TEMP_STEPS in config file
        local steps_string="("
        for step in "${new_steps[@]}"; do
            steps_string+="$step "
        done
        steps_string="${steps_string% })"  # Remove trailing space and add closing parenthesis
        
        sed -i "s/^TEMP_STEPS=.*/TEMP_STEPS=${steps_string}/" "$CONFIG_FILE"
        
        # Add the new threshold variable
        if ! grep -q "^TEMP_THRESHOLD_${temp}=" "$CONFIG_FILE"; then
            # Find where to insert the new threshold (after other thresholds)
            local insert_line=$(grep -n "^TEMP_THRESHOLD_.*=" "$CONFIG_FILE" | tail -1 | cut -d: -f1)
            if [[ -n $insert_line ]]; then
                sed -i "${insert_line}a\\TEMP_THRESHOLD_${temp}=${speed}             # Custom threshold (${temp}°C)" "$CONFIG_FILE"
            else
                echo "TEMP_THRESHOLD_${temp}=${speed}             # Custom threshold (${temp}°C)" >> "$CONFIG_FILE"
            fi
        fi
        
        print_color "$GREEN" "✓ Added new temperature step: ${temp}°C with fan speed ${speed}"
    fi
    
    print_color "$YELLOW" "⚠ Restart the service to apply changes: sudo systemctl restart ilo4-fan-control"
}

# Function to remove a temperature step
remove_temp_step() {
    local temp="$1"
    
    if ! [[ "$temp" =~ ^[0-9]+$ ]]; then
        print_color "$RED" "Invalid temperature. Must be a number"
        return 1
    fi
    
    if ! load_config; then
        return 1
    fi
    
    # Backup current config
    backup_config_internal
    
    # Load current configuration
    source "$CONFIG_FILE" 2>/dev/null
    
    # Check if temperature step exists
    local temp_exists=false
    for step in "${TEMP_STEPS[@]}"; do
        if [[ $step -eq $temp ]]; then
            temp_exists=true
            break
        fi
    done
    
    if [[ $temp_exists == false ]]; then
        print_color "$RED" "Temperature step ${temp}°C does not exist"
        return 1
    fi
    
    # Remove from TEMP_STEPS array
    local new_steps=()
    for step in "${TEMP_STEPS[@]}"; do
        if [[ $step -ne $temp ]]; then
            new_steps+=($step)
        fi
    done
    
    # Update TEMP_STEPS in config file
    local steps_string="("
    for step in "${new_steps[@]}"; do
        steps_string+="$step "
    done
    steps_string="${steps_string% })"  # Remove trailing space and add closing parenthesis
    
    sed -i "s/^TEMP_STEPS=.*/TEMP_STEPS=${steps_string}/" "$CONFIG_FILE"
    
    # Remove the threshold variable
    sed -i "/^TEMP_THRESHOLD_${temp}=/d" "$CONFIG_FILE"
    
    print_color "$GREEN" "✓ Removed temperature step: ${temp}°C"
    print_color "$YELLOW" "⚠ Restart the service to apply changes: sudo systemctl restart ilo4-fan-control"
}

# Function to list all available temperature steps
list_temp_steps() {
    if ! load_config; then
        return 1
    fi
    
    source "$CONFIG_FILE" 2>/dev/null
    
    print_color "$CYAN" "Available Temperature Steps:"
    print_color "$CYAN" "=========================="
    
    if [[ -n "${TEMP_STEPS[*]}" ]]; then
        local sorted_steps=($(printf '%s\n' "${TEMP_STEPS[@]}" | sort -nr))
        
        for step in "${sorted_steps[@]}"; do
            local threshold_var="TEMP_THRESHOLD_${step}"
            local speed="${!threshold_var:-"Not set"}"
            print_color "$YELLOW" "${step}°C → Fan Speed: ${speed}"
        done
        
        echo ""
        print_color "$YELLOW" "Default (below ${TEMP_STEPS[-1]}°C) → Fan Speed: ${TEMP_THRESHOLD_DEFAULT:-50}"
    else
        print_color "$RED" "No temperature steps configured"
    fi
}

# Main function
main() {
    case "${1:-}" in
        --show-thresholds|-s)
            show_thresholds
            ;;
        --set-threshold)
            if [[ $# -lt 3 ]]; then
                print_color "$RED" "Usage: $0 --set-threshold TEMP SPEED"
                exit 1
            fi
            set_threshold "$2" "$3"
            ;;
        --add-temp-step)
            if [[ $# -lt 3 ]]; then
                print_color "$RED" "Usage: $0 --add-temp-step TEMP SPEED"
                exit 1
            fi
            add_temp_step "$2" "$3"
            ;;
        --remove-temp-step)
            if [[ $# -lt 2 ]]; then
                print_color "$RED" "Usage: $0 --remove-temp-step TEMP"
                exit 1
            fi
            remove_temp_step "$2"
            ;;
        --list-temp-steps)
            list_temp_steps
            ;;
        --reset-thresholds)
            reset_thresholds
            ;;
        --show-config)
            show_config
            ;;
        --backup-config)
            backup_config
            ;;
        --restore-config)
            if [[ $# -lt 2 ]]; then
                print_color "$RED" "Usage: $0 --restore-config FILE"
                exit 1
            fi
            restore_config "$2"
            ;;
        --validate-config)
            validate_config
            ;;
        --test-connection)
            test_connection
            ;;
        --emergency-reset)
            emergency_reset
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

# Check if running as root for operations that need it
if [[ "${1:-}" =~ ^(--set-threshold|--add-temp-step|--remove-temp-step|--reset-thresholds|--restore-config|--emergency-reset)$ ]]; then
    if [[ $EUID -ne 0 ]]; then
        print_color "$RED" "This operation requires root privileges. Please run with sudo."
        exit 1
    fi
fi

# Execute main function
main "$@"
