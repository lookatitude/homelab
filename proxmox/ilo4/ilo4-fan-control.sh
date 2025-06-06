#!/bin/bash

# Enable strict error handling and logging
set -euo pipefail

# Set up logging
LOG_FILE="/var/log/ilo4-fan-control.log"
exec 1> >(tee -a "$LOG_FILE")
exec 2> >(tee -a "$LOG_FILE" >&2)

echo "$(date): Starting iLO4 fan control script..."

# === CONFIGURATION ===
ILO_HOST="<ip>"  # iLO IP or hostname
ILO_USER="<username>"

USE_SSH_PASS=true              # Set to false to use SSH key auth
ILO_PASS="<password>"           # Required only if USE_SSH_PASS=true

FAN_COUNT=6                    # Number of fans (fan 0 to FAN_COUNT-1)
GLOBAL_MIN_SPEED=60           # Minimum fan speed
PID_MIN_LOW=1600              # Minimum low for all PIDs
DISABLED_SENSORS=(07FB00 35 38)  # Sensors to turn off

# Dynamic fan control settings
ENABLE_DYNAMIC_CONTROL=true   # Set to false to disable dynamic control
MONITORING_INTERVAL=30        # Seconds between temperature checks
CPU1_FANS=(3 4 5)            # Fans controlled by CPU1 temperature
CPU2_FANS=(0 1 2)            # Fans controlled by CPU2 temperature

# Temperature thresholds and corresponding fan speeds
declare -A TEMP_THRESHOLDS=(
    [67]=255    # Emergency cooling
    [58]=39     # High temperature
    [54]=38     # Medium-high temperature
    [52]=34     # Medium temperature
    [50]=32     # Low-medium temperature
    [0]=30      # Default/idle temperature
)
# ========================

echo "LOGGING IN to iLO..."

# Build the SSH command options (safe legacy ciphers for iLO4)
SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -o ConnectTimeout=30
  -o ServerAliveInterval=10
  -o ServerAliveCountMax=3
  -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
  -o HostKeyAlgorithms=+ssh-rsa,ssh-dss
  -o PubkeyAcceptedAlgorithms=+ssh-rsa,ssh-dss
)

# Build the SSH command
if [ "$USE_SSH_PASS" = true ]; then
    if ! command -v sshpass &>/dev/null; then
        echo "ERROR: sshpass is not installed!"
        exit 1
    fi
    SSH_EXEC=(sshpass -p "$ILO_PASS" ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
else
    SSH_EXEC=(ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
fi

echo "SSH command: ${SSH_EXEC[*]}"

# Test SSH connection first
echo "Testing SSH connection to iLO..."
if timeout 30 "${SSH_EXEC[@]}" "version" &>/dev/null; then
    echo "SSH connection successful"
else
    echo "WARNING: SSH connection test failed, but continuing..."
fi

# --- Step 1: Get PIDs remotely ---
echo "Getting PID information from iLO..."
if ! PIDS_RAW=$(timeout 60 "${SSH_EXEC[@]}" "fan info g" 2>/dev/null | grep -oE '\[[^]]+\]' | tr -d '[]' | tr ' ' '\n' | sort -u | grep -v '^$'); then
    echo "WARNING: Failed to get PID information from iLO. Continuing with fan control..."
    PIDS_RAW=""
fi

if [ -z "$PIDS_RAW" ]; then
    echo "WARNING: No PIDs found. Continuing with fan control..."
else
    echo "Found PIDs: $PIDS_RAW"
fi

# Function to execute a single command on iLO with retry
execute_ilo_command() {
    local cmd="$1"
    local max_retries=3
    local retry=0
    
    while [ $retry -lt $max_retries ]; do
        echo "Executing: $cmd"
        # Use timeout to prevent hanging
        if timeout 30 "${SSH_EXEC[@]}" "$cmd" 2>&1; then
            echo "  ✓ Success"
            return 0
        else
            retry=$((retry + 1))
            echo "  ✗ Failed (attempt $retry/$max_retries)"
            if [ $retry -lt $max_retries ]; then
                echo "  Retrying in 3 seconds..."
                sleep 3
            fi
        fi
    done
    
    echo "  ✗ Command failed after $max_retries attempts: $cmd"
    return 1
}

# Wait for network to be ready (important for startup service)
echo "Waiting for network connectivity..."
for i in {1..30}; do
    if ping -c 1 "$ILO_HOST" >/dev/null 2>&1; then
        echo "iLO host $ILO_HOST is reachable"
        break
    fi
    echo "Waiting for network... ($i/30)"
    sleep 2
done

# --- Step 2: Execute fan commands individually ---
echo "Setting minimum fan speeds..."
for ((i=0; i < FAN_COUNT; i++)); do
    execute_ilo_command "fan p $i min $GLOBAL_MIN_SPEED"
    sleep 1  # Small delay between commands
done

echo "Setting PID minimums..."
while IFS= read -r pid; do
    [ -n "$pid" ] && execute_ilo_command "fan pid $pid lo $PID_MIN_LOW"
    sleep 1
done <<< "$PIDS_RAW"

echo "Disabling specified sensors..."
for sensor in "${DISABLED_SENSORS[@]}"; do
    execute_ilo_command "fan t $sensor off"
    sleep 1
done

echo "$(date): iLO4 fan control configuration completed successfully!"

# Function to get CPU temperature
get_cpu_temp() {
    local cpu_id="$1"
    local temp
    
    # Try to get temperature using sensors
    if command -v sensors &>/dev/null && command -v jq &>/dev/null; then
        temp=$(sensors -Aj "coretemp-isa-000$cpu_id" 2>/dev/null | jq '.[][] | to_entries[] | select(.key | endswith("input")) | .value' 2>/dev/null | sort -rn | head -n1)
        if [[ "$temp" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo "${temp%.*}"  # Remove decimal part
            return 0
        fi
    fi
    
    # Fallback: try reading from /sys
    local thermal_zone="/sys/class/thermal/thermal_zone$cpu_id/temp"
    if [[ -r "$thermal_zone" ]]; then
        temp=$(cat "$thermal_zone")
        echo $((temp / 1000))  # Convert millidegrees to degrees
        return 0
    fi
    
    echo "0"  # Default if no temperature found
    return 1
}

# Function to determine fan speed based on temperature
get_fan_speed_for_temp() {
    local temp="$1"
    local speed=30  # Default speed
    
    # Check temperature thresholds in descending order
    for threshold in 67 58 54 52 50; do
        if [[ $temp -ge $threshold ]]; then
            speed=${TEMP_THRESHOLDS[$threshold]}
            break
        fi
    done
    
    # Use default speed if no threshold matched
    if [[ $speed -eq 30 ]]; then
        speed=${TEMP_THRESHOLDS[0]}
    fi
    
    echo "$speed"
}

# Function to set fan speeds for a CPU
set_cpu_fan_speeds() {
    local cpu_num="$1"
    local temp="$2"
    local speed="$3"
    local fans_array_name="CPU${cpu_num}_FANS[@]"
    local fans=("${!fans_array_name}")
    
    echo "Setting CPU${cpu_num} fans (temp: ${temp}°C, speed: ${speed})"
    
    for fan in "${fans[@]}"; do
        if execute_ilo_command "fan p $fan max $speed"; then
            echo "  Fan $fan set to speed $speed"
        else
            echo "  Failed to set Fan $fan speed"
        fi
        sleep 0.5  # Small delay between fan commands
    done
}

# Function to monitor temperatures and adjust fans
monitor_and_control_fans() {
    echo "$(date): Starting dynamic fan control monitoring..."
    
    while true; do
        # Get CPU temperatures
        local cpu1_temp cpu2_temp
        cpu1_temp=$(get_cpu_temp 0)
        cpu2_temp=$(get_cpu_temp 1)
        
        echo "==============="
        echo "$(date): CPU1 Temp: ${cpu1_temp}°C, CPU2 Temp: ${cpu2_temp}°C"
        echo "==============="
        
        # Determine fan speeds based on temperatures
        local cpu1_speed cpu2_speed
        cpu1_speed=$(get_fan_speed_for_temp "$cpu1_temp")
        cpu2_speed=$(get_fan_speed_for_temp "$cpu2_temp")
        
        # Set fan speeds for each CPU
        set_cpu_fan_speeds 1 "$cpu1_temp" "$cpu1_speed"
        set_cpu_fan_speeds 2 "$cpu2_temp" "$cpu2_speed"
        
        echo "$(date): Fan control cycle completed. Sleeping for $MONITORING_INTERVAL seconds..."
        sleep "$MONITORING_INTERVAL"
    done
}

# Start dynamic fan control if enabled
if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
    echo "$(date): Dynamic fan control is enabled. Starting monitoring..."
    monitor_and_control_fans
else
    echo "$(date): Dynamic fan control is disabled. Initial setup complete."
fi

echo "Done."
