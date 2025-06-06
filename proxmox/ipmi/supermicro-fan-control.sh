#!/bin/bash

# Supermicro IPMI Fan Control Script for Proxmox/Debian
# Inspired by https://github.com/petersulyok/smfc
# Compatible with X10-X13 Supermicro motherboards using ipmitool
# 
# This script provides dynamic temperature-based fan control using IPMI
# and sets safe sensor thresholds to prevent IPMI from taking over control

set -euo pipefail

# Set up logging
LOG_FILE="/var/log/supermicro-fan-control.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting Supermicro IPMI fan control script..."

# === CONFIGURATION ===
# IPMI settings
IPMITOOL_CMD="/usr/bin/ipmitool"           # Path to ipmitool
USE_SUDO=true                              # Use sudo for ipmitool commands
IPMI_USER="ADMIN"                          # Remote IPMI user (leave empty for local)
IPMI_PASS="ADMIN"                          # Remote IPMI password
IPMI_HOST="192.168.1.100"                  # Remote IPMI host

# Fan control mode
FAN_MODE=1                                 # IPMI fan mode: STANDARD=0, FULL=1, OPTIMAL=2, PUE=3, HEAVY_IO=4
FAN_MODE_DELAY=10                          # Delay after setting fan mode (seconds)
FAN_LEVEL_DELAY=2                          # Delay after setting fan level (seconds)

# Temperature-based fan control
ENABLE_DYNAMIC_CONTROL=true                # Enable dynamic temperature control
INTERVAL=30                                # Temperature monitoring interval (seconds)
TEMP_SENSITIVITY=2.0                       # Temperature change threshold to trigger fan adjustment (°C)

# CPU Zone (Zone 0) configuration
CPU_ZONE_ENABLED=true
CPU_TEMP_LOW=35                            # Low CPU temperature (°C)
CPU_TEMP_HIGH=70                           # High CPU temperature (°C)
CPU_MIN_FAN=25                             # Minimum fan level (%)
CPU_MAX_FAN=100                            # Maximum fan level (%)
CPU_TEMP_CALC="max"                        # Temperature calculation: min, avg, max
CPU_TEMP_STEPS=6                           # Discrete steps for temperature mapping

# HD Zone (Zone 1) configuration  
HD_ZONE_ENABLED=true
HD_TEMP_LOW=30                             # Low HD temperature (°C)
HD_TEMP_HIGH=45                            # High HD temperature (°C)
HD_MIN_FAN=25                              # Minimum fan level (%)
HD_MAX_FAN=80                              # Maximum fan level (%)
HD_TEMP_CALC="max"                         # Temperature calculation: min, avg, max
HD_TEMP_STEPS=4                            # Discrete steps for temperature mapping
HD_DEVICE_PATTERN="/dev/sd[a-z]"           # Pattern to match HD devices

# Temperature monitoring sources
ENABLE_THERMAL_ZONES=true                  # Enable /sys/class/thermal monitoring
ENABLE_SENSORS=true                        # Enable sensors command monitoring  
ENABLE_IPMI_SENSORS=true                   # Enable IPMI sensor monitoring
ENABLE_HD_MONITORING=true                  # Enable hard drive temperature monitoring

# Sensor threshold configuration (prevents IPMI takeover)
SET_THRESHOLDS=true                        # Enable threshold setting
THRESHOLD_LOWER=(0 100 200)                # Lower thresholds: non-recoverable, critical, non-critical
THRESHOLD_UPPER=(1600 1700 1800)           # Upper thresholds: non-critical, critical, non-recoverable

# Fan configuration for different motherboard types
# Common fan names for Supermicro boards
CPU_FANS=("FAN1" "FAN2" "FAN3" "FAN4")     # CPU zone fans
PERIPHERAL_FANS=("FANA" "FANB" "FANC" "FAND") # Peripheral zone fans

# Global variables for state tracking
declare -A LAST_TEMP_CPU
declare -A LAST_TEMP_HD
declare -A LAST_FAN_LEVEL
LAST_CHECK_TIME=0

# === HELPER FUNCTIONS ===

# Log function with timestamp
log() {
    local level="$1"
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
}

# Execute ipmitool command with proper error handling
exec_ipmitool() {
    local args=("$@")
    local cmd_args=()
    
    # Add sudo if needed
    if [[ "$USE_SUDO" == "true" ]] && [[ $EUID -ne 0 ]]; then
        cmd_args+=("sudo")
    fi
    
    # Add ipmitool command
    cmd_args+=("$IPMITOOL_CMD")
    
    # Add remote parameters if configured
    if [[ -n "$IPMI_USER" ]] && [[ -n "$IPMI_PASS" ]] && [[ -n "$IPMI_HOST" ]]; then
        cmd_args+=("-I" "lanplus" "-U" "$IPMI_USER" "-P" "$IPMI_PASS" "-H" "$IPMI_HOST")
    fi
    
    # Add command arguments
    cmd_args+=("${args[@]}")
    
    # Execute with timeout and error handling
    if ! timeout 30 "${cmd_args[@]}" 2>/dev/null; then
        log "ERROR" "IPMI command failed: ${cmd_args[*]}"
        return 1
    fi
    return 0
}

# Set IPMI fan mode
set_fan_mode() {
    local mode="$1"
    local mode_num
    
    case "$mode" in
        "STANDARD") mode_num="0x00" ;;
        "FULL") mode_num="0x01" ;;
        "OPTIMAL") mode_num="0x02" ;;
        "PUE") mode_num="0x03" ;;
        "HEAVY_IO") mode_num="0x04" ;;
        *) log "ERROR" "Invalid fan mode: $mode"; return 1 ;;
    esac
    
    log "INFO" "Setting IPMI fan mode to $mode"
    if exec_ipmitool raw 0x30 0x45 0x01 "$mode_num"; then
        sleep "$FAN_MODE_DELAY"
        log "INFO" "Fan mode set to $mode successfully"
        return 0
    else
        log "ERROR" "Failed to set fan mode to $mode"
        return 1
    fi
}

# Set fan level for specific zone
set_fan_level() {
    local zone="$1"
    local level="$2"
    
    # Validate inputs
    if [[ ! "$zone" =~ ^[0-9]+$ ]] || (( zone < 0 || zone > 100 )); then
        log "ERROR" "Invalid zone: $zone"
        return 1
    fi
    
    if [[ ! "$level" =~ ^[0-9]+$ ]] || (( level < 0 || level > 100 )); then
        log "ERROR" "Invalid fan level: $level"
        return 1
    fi
    
    local zone_hex
    local level_hex
    zone_hex=$(printf "0x%02x" "$zone")
    level_hex=$(printf "0x%02x" "$level")
    
    if exec_ipmitool raw 0x30 0x70 0x66 0x01 "$zone_hex" "$level_hex"; then
        sleep "$FAN_LEVEL_DELAY"
        log "DEBUG" "Set zone $zone fan level to $level%"
        return 0
    else
        log "ERROR" "Failed to set zone $zone fan level to $level%"
        return 1
    fi
}

# Get current fan level for zone
get_fan_level() {
    local zone="$1"
    local zone_hex
    zone_hex=$(printf "0x%02x" "$zone")
    
    local result
    if result=$(exec_ipmitool raw 0x30 0x70 0x66 0x00 "$zone_hex" 2>/dev/null); then
        # Convert hex result to decimal
        printf "%d" "$result" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Set sensor thresholds for a fan
set_fan_thresholds() {
    local fan_name="$1"
    
    # Set lower thresholds
    if exec_ipmitool sensor thresh "$fan_name" lower "${THRESHOLD_LOWER[0]}" "${THRESHOLD_LOWER[1]}" "${THRESHOLD_LOWER[2]}"; then
        log "DEBUG" "Set lower thresholds for $fan_name: ${THRESHOLD_LOWER[*]}"
    else
        log "WARN" "Failed to set lower thresholds for $fan_name"
    fi
    
    # Set upper thresholds  
    if exec_ipmitool sensor thresh "$fan_name" upper "${THRESHOLD_UPPER[0]}" "${THRESHOLD_UPPER[1]}" "${THRESHOLD_UPPER[2]}"; then
        log "DEBUG" "Set upper thresholds for $fan_name: ${THRESHOLD_UPPER[*]}"
    else
        log "WARN" "Failed to set upper thresholds for $fan_name"
    fi
}

# Auto-detect available fans
detect_fans() {
    local fan_list=()
    
    # Get sensor data and extract fan names
    if sensor_data=$(exec_ipmitool sdr list 2>/dev/null); then
        while IFS= read -r line; do
            if [[ "$line" =~ ^(FAN[0-9A-Z]+)[[:space:]] ]]; then
                fan_list+=("${BASH_REMATCH[1]}")
            fi
        done <<< "$sensor_data"
    fi
    
    printf "%s\n" "${fan_list[@]}"
}

# Get CPU temperature (average of all cores)
get_cpu_temperature() {
    local temps=()
    local temp_sum=0
    local temp_count=0
    
    # Try to get temperatures from different sources
    
    # Method 1: /sys/class/thermal
    if [[ "$ENABLE_THERMAL_ZONES" == "true" ]] && [[ -d "/sys/class/thermal" ]]; then
        for thermal_zone in /sys/class/thermal/thermal_zone*/temp; do
            if [[ -r "$thermal_zone" ]]; then
                local temp_millic
                if temp_millic=$(cat "$thermal_zone" 2>/dev/null); then
                    local temp_c=$((temp_millic / 1000))
                    if (( temp_c > 0 && temp_c < 150 )); then
                        temps+=("$temp_c")
                    fi
                fi
            fi
        done
    fi
    
    # Method 2: sensors command (if available)
    if [[ "$ENABLE_SENSORS" == "true" ]] && command -v sensors >/dev/null 2>&1 && [[ ${#temps[@]} -eq 0 ]]; then
        local sensor_output
        if sensor_output=$(sensors 2>/dev/null); then
            while IFS= read -r line; do
                if [[ "$line" =~ Core\ [0-9]+:.*\+([0-9]+\.[0-9]+)°C ]]; then
                    local temp="${BASH_REMATCH[1]}"
                    temps+=("${temp%.*}")  # Convert to integer
                fi
            done <<< "$sensor_output"
        fi
    fi
    
    # Method 3: IPMI sensors
    if [[ "$ENABLE_IPMI_SENSORS" == "true" ]] && [[ ${#temps[@]} -eq 0 ]]; then
        local ipmi_output
        if ipmi_output=$(exec_ipmitool sdr type temperature 2>/dev/null); then
            while IFS= read -r line; do
                if [[ "$line" =~ CPU.*Temp.*\|.*([0-9]+).*degrees ]]; then
                    temps+=("${BASH_REMATCH[1]}")
                fi
            done <<< "$ipmi_output"
        fi
    fi
    
    # Calculate based on specified method
    if [[ ${#temps[@]} -gt 0 ]]; then
        case "$CPU_TEMP_CALC" in
            "min")
                printf "%s\n" "${temps[@]}" | sort -n | head -1
                ;;
            "max")
                printf "%s\n" "${temps[@]}" | sort -n | tail -1
                ;;
            "avg"|*)
                for temp in "${temps[@]}"; do
                    temp_sum=$((temp_sum + temp))
                    temp_count=$((temp_count + 1))
                done
                echo $((temp_sum / temp_count))
                ;;
        esac
    else
        echo "40"  # Default fallback temperature
    fi
}

# Get hard drive temperatures
get_hd_temperature() {
    local temps=()
    local hd_devices=()
    
    # Return default if HD monitoring is disabled
    if [[ "$ENABLE_HD_MONITORING" != "true" ]]; then
        echo "30"  # Default safe temperature
        return 0
    fi
    
    # Find hard drive devices
    for device in $HD_DEVICE_PATTERN; do
        if [[ -b "$device" ]]; then
            hd_devices+=("$device")
        fi
    done
    
    # Get temperatures using smartctl or hddtemp
    for device in "${hd_devices[@]}"; do
        local temp=""
        
        # Try smartctl first
        if command -v smartctl >/dev/null 2>&1; then
            local smartctl_output
            if smartctl_output=$(smartctl -A "$device" 2>/dev/null); then
                if [[ "$smartctl_output" =~ Temperature_Celsius.*[[:space:]]([0-9]+) ]]; then
                    temp="${BASH_REMATCH[1]}"
                fi
            fi
        fi
        
        # Try hddtemp if smartctl failed
        if [[ -z "$temp" ]] && command -v hddtemp >/dev/null 2>&1; then
            local hddtemp_output
            if hddtemp_output=$(hddtemp "$device" 2>/dev/null); then
                if [[ "$hddtemp_output" =~ :\ ([0-9]+)°C ]]; then
                    temp="${BASH_REMATCH[1]}"
                fi
            fi
        fi
        
        if [[ -n "$temp" ]] && (( temp > 0 && temp < 100 )); then
            temps+=("$temp")
        fi
    done
    
    # Calculate based on specified method
    if [[ ${#temps[@]} -gt 0 ]]; then
        case "$HD_TEMP_CALC" in
            "min")
                printf "%s\n" "${temps[@]}" | sort -n | head -1
                ;;
            "max")
                printf "%s\n" "${temps[@]}" | sort -n | tail -1
                ;;
            "avg"|*)
                local temp_sum=0
                for temp in "${temps[@]}"; do
                    temp_sum=$((temp_sum + temp))
                done
                echo $((temp_sum / ${#temps[@]}))
                ;;
        esac
    else
        echo "30"  # Default fallback temperature
    fi
}

# Calculate fan level based on temperature
calculate_fan_level() {
    local current_temp="$1"
    local min_temp="$2"
    local max_temp="$3"
    local min_level="$4"
    local max_level="$5"
    local steps="$6"
    
    # Convert to integer arithmetic (multiply by 10 for one decimal precision)
    local current_temp_int=$((${current_temp%.*} * 10 + ${current_temp#*.}))
    local min_temp_int=$((${min_temp%.*} * 10 + ${min_temp#*.}))
    local max_temp_int=$((${max_temp%.*} * 10 + ${max_temp#*.}))
    
    # Calculate fan level
    if (( current_temp_int <= min_temp_int )); then
        echo "$min_level"
    elif (( current_temp_int >= max_temp_int )); then
        echo "$max_level"
    else
        local temp_range=$((max_temp_int - min_temp_int))
        local level_range=$((max_level - min_level))
        local temp_above_min=$((current_temp_int - min_temp_int))
        
        local gain=$((temp_above_min * steps / temp_range))
        local fan_level=$((min_level + gain * level_range / steps))
        
        echo "$fan_level"
    fi
}

# Main temperature monitoring and fan control loop
run_fan_control() {
    local current_time
    current_time=$(date +%s)
    
    # Check if enough time has passed since last check
    if (( current_time - LAST_CHECK_TIME < INTERVAL )); then
        return 0
    fi
    
    LAST_CHECK_TIME="$current_time"
    
    # CPU Zone control
    if [[ "$CPU_ZONE_ENABLED" == "true" ]]; then
        local cpu_temp
        cpu_temp=$(get_cpu_temperature)
        log "DEBUG" "Current CPU temperature: ${cpu_temp}°C"
        
        # Check temperature sensitivity
        local last_cpu_temp="${LAST_TEMP_CPU[0]:-0}"
        local temp_diff
        temp_diff=$(echo "$cpu_temp - $last_cpu_temp" | bc -l 2>/dev/null || echo "10")
        
        if (( $(echo "${temp_diff#-} >= $TEMP_SENSITIVITY" | bc -l 2>/dev/null) )); then
            LAST_TEMP_CPU[0]="$cpu_temp"
            
            local new_level
            new_level=$(calculate_fan_level "$cpu_temp" "$CPU_TEMP_LOW" "$CPU_TEMP_HIGH" "$CPU_MIN_FAN" "$CPU_MAX_FAN" "$CPU_TEMP_STEPS")
            
            local current_level="${LAST_FAN_LEVEL[0]:-0}"
            if [[ "$new_level" != "$current_level" ]]; then
                log "INFO" "CPU zone: Temperature ${cpu_temp}°C, setting fan level to ${new_level}%"
                if set_fan_level 0 "$new_level"; then
                    LAST_FAN_LEVEL[0]="$new_level"
                fi
            fi
        fi
    fi
    
    # HD Zone control
    if [[ "$HD_ZONE_ENABLED" == "true" ]]; then
        local hd_temp
        hd_temp=$(get_hd_temperature)
        log "DEBUG" "Current HD temperature: ${hd_temp}°C"
        
        # Check temperature sensitivity
        local last_hd_temp="${LAST_TEMP_HD[0]:-0}"
        local temp_diff
        temp_diff=$(echo "$hd_temp - $last_hd_temp" | bc -l 2>/dev/null || echo "10")
        
        if (( $(echo "${temp_diff#-} >= $TEMP_SENSITIVITY" | bc -l 2>/dev/null) )); then
            LAST_TEMP_HD[0]="$hd_temp"
            
            local new_level
            new_level=$(calculate_fan_level "$hd_temp" "$HD_TEMP_LOW" "$HD_TEMP_HIGH" "$HD_MIN_FAN" "$HD_MAX_FAN" "$HD_TEMP_STEPS")
            
            local current_level="${LAST_FAN_LEVEL[1]:-0}"
            if [[ "$new_level" != "$current_level" ]]; then
                log "INFO" "HD zone: Temperature ${hd_temp}°C, setting fan level to ${new_level}%"
                if set_fan_level 1 "$new_level"; then
                    LAST_FAN_LEVEL[1]="$new_level"
                fi
            fi
        fi
    fi
}

# Initialize the system
initialize_system() {
    log "INFO" "Initializing Supermicro fan control system..."
    
    # Check if ipmitool is available
    if ! command -v "$IPMITOOL_CMD" >/dev/null 2>&1; then
        log "ERROR" "ipmitool not found at $IPMITOOL_CMD"
        exit 1
    fi
    
    # Test IPMI connectivity
    if ! exec_ipmitool sdr list >/dev/null 2>&1; then
        log "ERROR" "Failed to connect to IPMI. Check configuration and permissions."
        exit 1
    fi
    
    # Set fan mode
    if ! set_fan_mode "$FAN_MODE"; then
        log "ERROR" "Failed to set fan mode"
        exit 1
    fi
    
    # Set sensor thresholds if enabled
    if [[ "$SET_THRESHOLDS" == "true" ]]; then
        log "INFO" "Setting sensor thresholds..."
        
        # Auto-detect fans and set thresholds
        local detected_fans
        mapfile -t detected_fans < <(detect_fans)
        
        for fan in "${detected_fans[@]}"; do
            set_fan_thresholds "$fan"
        done
        
        log "INFO" "Sensor thresholds configured for ${#detected_fans[@]} fans"
    fi
    
    # Set initial fan levels
    if [[ "$CPU_ZONE_ENABLED" == "true" ]]; then
        log "INFO" "Setting initial CPU zone fan level to ${CPU_MIN_FAN}%"
        set_fan_level 0 "$CPU_MIN_FAN"
    fi
    
    if [[ "$HD_ZONE_ENABLED" == "true" ]]; then
        log "INFO" "Setting initial HD zone fan level to ${HD_MIN_FAN}%"
        set_fan_level 1 "$HD_MIN_FAN"
    fi
    
    log "INFO" "System initialization completed"
}

# Cleanup function
cleanup() {
    log "INFO" "Shutting down fan control system..."
    
    # Reset to safe fan levels
    if [[ "$CPU_ZONE_ENABLED" == "true" ]]; then
        log "INFO" "Resetting CPU zone to safe level"
        set_fan_level 0 "$CPU_MAX_FAN"
    fi
    
    if [[ "$HD_ZONE_ENABLED" == "true" ]]; then
        log "INFO" "Resetting HD zone to safe level"
        set_fan_level 1 "$HD_MAX_FAN"
    fi
    
    log "INFO" "Fan control system stopped"
    exit 0
}

# Signal handlers
trap cleanup SIGTERM SIGINT

# === MAIN EXECUTION ===

# Check if running as daemon or one-shot
if [[ "${1:-}" == "--daemon" ]]; then
    log "INFO" "Starting in daemon mode..."
    initialize_system
    
    # Main loop
    while true; do
        if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
            run_fan_control
        fi
        sleep 5  # Short sleep, actual interval controlled by run_fan_control
    done
elif [[ "${1:-}" == "--init-only" ]]; then
    log "INFO" "Running initialization only..."
    initialize_system
    log "INFO" "Initialization complete. Exiting."
elif [[ "${1:-}" == "--set-thresholds" ]]; then
    log "INFO" "Setting thresholds only..."
    
    if [[ "$SET_THRESHOLDS" == "true" ]]; then
        # Auto-detect fans and set thresholds
        local detected_fans
        mapfile -t detected_fans < <(detect_fans)
        
        for fan in "${detected_fans[@]}"; do
            set_fan_thresholds "$fan"
        done
        
        log "INFO" "Thresholds set for ${#detected_fans[@]} fans"
    else
        log "INFO" "Threshold setting is disabled in configuration"
    fi
elif [[ "${1:-}" == "--status" ]]; then
    log "INFO" "Current system status:"
    
    # Show current fan levels
    local cpu_level
    local hd_level
    cpu_level=$(get_fan_level 0)
    hd_level=$(get_fan_level 1)
    
    log "INFO" "CPU Zone (0): ${cpu_level}%"
    log "INFO" "HD Zone (1): ${hd_level}%"
    
    # Show temperatures
    local cpu_temp
    local hd_temp
    cpu_temp=$(get_cpu_temperature)
    hd_temp=$(get_hd_temperature)
    
    log "INFO" "CPU Temperature: ${cpu_temp}°C"
    log "INFO" "HD Temperature: ${hd_temp}°C"
    
    # Show detected fans
    local detected_fans
    mapfile -t detected_fans < <(detect_fans)
    log "INFO" "Detected fans: ${detected_fans[*]}"
elif [[ "${1:-}" == "--once" ]]; then
    log "INFO" "Running one-shot initialization and control..."
    initialize_system
    
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        run_fan_control
    fi
    
    log "INFO" "One-shot execution completed"
elif [[ "${1:-}" == "--test" ]]; then
    log "INFO" "Running in test mode (no actual changes)..."
    
    # Test IPMI connectivity
    if exec_ipmitool sdr list >/dev/null 2>&1; then
        log "INFO" "✓ IPMI connection successful"
    else
        log "ERROR" "✗ IPMI connection failed"
        exit 1
    fi
    
    # Test temperature reading
    local cpu_temp
    local hd_temp
    cpu_temp=$(get_cpu_temperature)
    hd_temp=$(get_hd_temperature)
    
    log "INFO" "Current CPU Temperature: ${cpu_temp}°C"
    log "INFO" "Current HD Temperature: ${hd_temp}°C"
    
    # Show detected fans
    local detected_fans
    mapfile -t detected_fans < <(detect_fans)
    log "INFO" "Detected fans: ${detected_fans[*]}"
    
    log "INFO" "Test completed successfully"
else
    log "INFO" "Running one-shot initialization and control..."
    initialize_system
    
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        run_fan_control
    fi
    
    log "INFO" "One-shot execution completed"
fi
