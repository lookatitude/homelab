#!/bin/bash

# HP iLO4 Fan Control Script
# Provides comprehensive fan control for HP iLO4-equipped servers
# Supports dynamic temperature-based control and manual configuration

set -euo pipefail

# Script version and info
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="iLO4 Fan Control"

# Default configuration file paths
CONFIG_FILE="/etc/ilo4-fan-control/ilo4-fan-control.conf"
LOCAL_CONFIG_FILE="./ilo4-fan-control.conf"

# Default values (can be overridden by config file)
ILO_HOST="<ip>"
ILO_USER="<username>"
ILO_PASS="<password>"
USE_SSH_PASS=true
FAN_COUNT=6
GLOBAL_MIN_SPEED=60
PID_MIN_LOW=1600
DISABLED_SENSORS=(07FB00 35 38)
ENABLE_DYNAMIC_CONTROL=true
MONITORING_INTERVAL=30
CPU1_FANS=(3 4 5)
CPU2_FANS=(0 1 2)
MAX_TEMP_CPU=80
EMERGENCY_SPEED=255
CONNECTION_TIMEOUT=30
COMMAND_RETRIES=3
LOG_LEVEL="INFO"
LOG_FILE="/var/log/ilo4-fan-control.log"
MAX_LOG_SIZE="50M"
LOG_RETENTION_DAYS=30
NETWORK_CHECK_RETRIES=30
NETWORK_CHECK_INTERVAL=2
SSH_ALIVE_INTERVAL=10
SSH_ALIVE_COUNT_MAX=3

# Temperature thresholds and steps
TEMP_STEPS=(90 80 70 60 50)       # Default temperature steps (configurable)
TEMP_THRESHOLD_90=255
TEMP_THRESHOLD_80=200
TEMP_THRESHOLD_70=150
TEMP_THRESHOLD_60=100
TEMP_THRESHOLD_50=75
TEMP_THRESHOLD_DEFAULT=50

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored log messages
log_message() {
    local level="$1"
    local message="$2"
    local timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    local color=""
    
    case "$level" in
        "ERROR") color="$RED" ;;
        "WARN")  color="$YELLOW" ;;
        "INFO")  color="$GREEN" ;;
        "DEBUG") color="$BLUE" ;;
        *)       color="$NC" ;;
    esac
    
    # Check log level filtering
    case "$LOG_LEVEL" in
        "DEBUG") ;; # Show all
        "INFO")  [[ "$level" =~ ^(ERROR|WARN|INFO)$ ]] || return ;;
        "WARN")  [[ "$level" =~ ^(ERROR|WARN)$ ]] || return ;;
        "ERROR") [[ "$level" == "ERROR" ]] || return ;;
    esac
    
    echo -e "${color}[$timestamp] [$level] $message${NC}"
}

# Function to load configuration
load_config() {
    local config_path=""
    
    # Check for configuration file in order of preference
    if [[ -f "$CONFIG_FILE" ]]; then
        config_path="$CONFIG_FILE"
    elif [[ -f "$LOCAL_CONFIG_FILE" ]]; then
        config_path="$LOCAL_CONFIG_FILE"
    else
        log_message "WARN" "No configuration file found. Using default values."
        return 0
    fi
    
    log_message "INFO" "Loading configuration from: $config_path"
    
    # Source the configuration file in a subshell to avoid security issues
    if ! source "$config_path"; then
        log_message "ERROR" "Failed to load configuration file: $config_path"
        return 1
    fi
    
    log_message "INFO" "Configuration loaded successfully"
    return 0
}

# Function to validate configuration
validate_config() {
    local errors=0
    
    # Validate required settings
    if [[ "$ILO_HOST" == "<ip>" ]]; then
        log_message "ERROR" "ILO_HOST must be configured"
        ((errors++))
    fi
    
    if [[ "$ILO_USER" == "<username>" ]]; then
        log_message "ERROR" "ILO_USER must be configured"
        ((errors++))
    fi
    
    if [[ "$USE_SSH_PASS" == "true" && "$ILO_PASS" == "<password>" ]]; then
        log_message "ERROR" "ILO_PASS must be configured when using password authentication"
        ((errors++))
    fi
    
    # Validate numeric values
    if ! [[ "$FAN_COUNT" =~ ^[0-9]+$ ]] || [[ "$FAN_COUNT" -lt 1 ]] || [[ "$FAN_COUNT" -gt 20 ]]; then
        log_message "ERROR" "FAN_COUNT must be a number between 1 and 20"
        ((errors++))
    fi
    
    if ! [[ "$GLOBAL_MIN_SPEED" =~ ^[0-9]+$ ]] || [[ "$GLOBAL_MIN_SPEED" -lt 0 ]] || [[ "$GLOBAL_MIN_SPEED" -gt 255 ]]; then
        log_message "ERROR" "GLOBAL_MIN_SPEED must be a number between 0 and 255"
        ((errors++))
    fi
    
    if ! [[ "$MONITORING_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$MONITORING_INTERVAL" -lt 5 ]] || [[ "$MONITORING_INTERVAL" -gt 3600 ]]; then
        log_message "ERROR" "MONITORING_INTERVAL must be a number between 5 and 3600 seconds"
        ((errors++))
    fi
    
    if [[ $errors -gt 0 ]]; then
        log_message "ERROR" "Configuration validation failed with $errors errors"
        return 1
    fi
    
    log_message "INFO" "Configuration validation passed"
    return 0
}

# Function to set up logging
setup_logging() {
    # Create log directory if it doesn't exist
    local log_dir="$(dirname \"$LOG_FILE\")"
    if [[ ! -d "$log_dir" ]]; then
        if [[ ! -w "$(dirname $log_dir)" ]]; then
            log_message "WARN" "Cannot create log directory: $log_dir. Skipping log setup due to read-only file system."
        else
            mkdir -p "$log_dir" || {
                log_message "ERROR" "Cannot create log directory: $log_dir"
                exit 1
            }
        fi
    fi

    # Set up log rotation if logrotate is available
    if command -v logrotate &>/dev/null; then
        local logrotate_config="/etc/logrotate.d/ilo4-fan-control"
        if [[ ! -w "/etc/logrotate.d" ]]; then
            log_message "WARN" "Cannot write to /etc/logrotate.d. Skipping logrotate configuration."
        elif [[ ! -f "$logrotate_config" ]]; then
            cat > "$logrotate_config" << EOF
$LOG_FILE {
    daily
    rotate $LOG_RETENTION_DAYS
    compress
    delaycompress
    missingok
    notifempty
    size $MAX_LOG_SIZE
    create 644 root root
}
EOF
        fi
    fi

    # Redirect output to log file
    exec 1> >(tee -a "$LOG_FILE")
    exec 2> >(tee -a "$LOG_FILE" >&2)
}

# Function to show script info
show_info() {
    log_message "INFO" "=========================================="
    log_message "INFO" "$SCRIPT_NAME v$SCRIPT_VERSION"
    log_message "INFO" "=========================================="
    log_message "INFO" "iLO Host: $ILO_HOST"
    log_message "INFO" "iLO User: $ILO_USER"
    log_message "INFO" "Fan Count: $FAN_COUNT"
    log_message "INFO" "Dynamic Control: $ENABLE_DYNAMIC_CONTROL"
    log_message "INFO" "Log Level: $LOG_LEVEL"
    log_message "INFO" "=========================================="
}

# Initialize script
main_init() {
    # Load configuration
    if ! load_config; then
        log_message "ERROR" "Failed to load configuration"
        exit 1
    fi
    
    # Set up logging
    setup_logging
    
    # Show script info
    show_info
    
    # Validate configuration
    if ! validate_config; then
        log_message "ERROR" "Configuration validation failed"
        exit 1
    fi
    
    log_message "INFO" "Starting iLO4 fan control script..."
}

# Call initialization
main_init

log_message "INFO" "Initializing SSH connection to iLO..."

# Build the SSH command options (safe legacy ciphers for iLO4)
SSH_OPTS=(
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout="$CONNECTION_TIMEOUT"
    -o ServerAliveInterval="$SSH_ALIVE_INTERVAL"
    -o ServerAliveCountMax="$SSH_ALIVE_COUNT_MAX"
    -o KexAlgorithms=+diffie-hellman-group14-sha1,diffie-hellman-group1-sha1
    -o HostKeyAlgorithms=+ssh-rsa,ssh-dss
    -o PubkeyAcceptedAlgorithms=+ssh-rsa,ssh-dss
)

# Build the SSH command
if [[ "$USE_SSH_PASS" == "true" ]]; then
    if ! command -v sshpass &>/dev/null; then
        log_message "ERROR" "sshpass is not installed! Install with: apt install sshpass"
        exit 1
    fi
    SSH_EXEC=(sshpass -p "$ILO_PASS" ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
else
    SSH_EXEC=(ssh "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
fi

log_message "DEBUG" "SSH command configured: ${SSH_EXEC[*]}"

# Function to test SSH connection
# Always use a non-interactive command ("exit" or "version") to avoid hanging
# Returns 0 on success, 1 on failure
test_ssh_connection() {
    log_message "INFO" "Testing SSH connection to iLO..."
    local test_attempts=3
    local attempt=1
    while [[ $attempt -le $test_attempts ]]; do
        log_message "DEBUG" "Connection test attempt $attempt/$test_attempts"
        log_message "DEBUG" "Executing SSH command: ${SSH_EXEC[*]} exit"
        output=$("${SSH_EXEC[@]}" exit 2>&1)
        # Accept iLO4's normal output as success
        if [[ "$output" == *"status=0"* || "$output" == *"status_tag=COMMAND COMPLETED"* ]]; then
            log_message "INFO" "SSH connection successful (iLO4 normal output detected)"
            return 0
        else
            log_message "ERROR" "SSH command failed with error: $output"
            ((attempt++))
            sleep 2
        fi
    done
    log_message "ERROR" "SSH connection failed after $test_attempts attempts"
    return 1
}

# Function to handle CLI session timeouts and retry SSH connection
detect_and_retry_ssh_timeout() {
    local cmd="$1"
    local max_retries=5
    local retry_interval=5
    local attempt=1

    while [[ $attempt -le $max_retries ]]; do
        log_message "DEBUG" "Attempting SSH command (attempt $attempt/$max_retries): $cmd"

        if output=$(timeout "$CONNECTION_TIMEOUT" "${SSH_EXEC[@]}" "$cmd" 2>&1); then
            log_message "INFO" "SSH command executed successfully: $cmd"
            echo "$output"
            return 0
        else
            if [[ "$output" =~ "CLI session timed out" ]]; then
                log_message "WARN" "CLI session timed out. Retrying in $retry_interval seconds..."
                sleep "$retry_interval"
                ((attempt++))
            else
                log_message "ERROR" "SSH command failed with error: $output"
                return 1
            fi
        fi
    done

    log_message "ERROR" "SSH command failed after $max_retries attempts: $cmd"
    return 1
}

# Update the execute_ilo_command function to use the new retry mechanism
execute_ilo_command() {
    local cmd="$1"
    local retry=0
    local empty_output_retries=2  # Number of extra retries for empty output
    while [[ $retry -lt $COMMAND_RETRIES ]]; do
        log_message "DEBUG" "Executing iLO command: $cmd"
        # Use timeout to prevent hanging
        if output=$(timeout "$CONNECTION_TIMEOUT" "${SSH_EXEC[@]}" "$cmd" 2>&1); then
            log_message "DEBUG" "Command executed successfully: $cmd"
            # Validate response
            if [[ -n "$output" ]]; then
                log_message "INFO" "Received valid response: $output"
                echo "$output"
                return 0
            else
                log_message "WARN" "iLO4 returned empty output for command: '$cmd'. This is a known iLO4 quirk (especially after reboot). Will retry $empty_output_retries more times."
                local empty_retry=1
                while [[ $empty_retry -le $empty_output_retries ]]; do
                    sleep 2
                    log_message "INFO" "Retrying command due to empty output (attempt $empty_retry/$empty_output_retries)..."
                    output=$(timeout "$CONNECTION_TIMEOUT" "${SSH_EXEC[@]}" "$cmd" 2>&1)
                    if [[ -n "$output" ]]; then
                        log_message "INFO" "Received valid response after retry: $output"
                        echo "$output"
                        return 0
                    fi
                    ((empty_retry++))
                done
                log_message "ERROR" "iLO4 returned empty output for command: '$cmd' after $empty_output_retries retries. Giving up on this command."
            fi
        else
            log_message "ERROR" "Command failed (attempt $((retry + 1))/$COMMAND_RETRIES): $cmd"
            log_message "DEBUG" "Error output: $output"
            # Check for session timeout error
            if [[ "$output" =~ "CLI session timed out" ]]; then
                handle_ssh_timeout
            fi
        fi
        ((retry++))
        if [[ $retry -lt $COMMAND_RETRIES ]]; then
            log_message "DEBUG" "Retrying in 3 seconds..."
            sleep 3
        fi
    done
    log_message "ERROR" "Command failed after $COMMAND_RETRIES attempts: $cmd"
    exit 1
}

# Function to detect and retry SSH session timeout
handle_ssh_timeout() {
    log_message "WARN" "Detected SSH session timeout. Attempting to reconnect..."

    # Reinitialize SSH connection
    if ! test_ssh_connection; then
        log_message "ERROR" "Failed to reinitialize SSH connection after timeout. Exiting."
        exit 1
    fi

    log_message "INFO" "SSH connection reinitialized successfully."
}

# Enhanced `execute_ilo_command` function with timeout and forced exit
execute_ilo_command() {
    local cmd="$1"
    local retry=0

    while [[ $retry -lt $COMMAND_RETRIES ]]; do
        log_message "DEBUG" "Executing iLO command: $cmd"

        # Use timeout to prevent hanging
        if output=$(timeout "$CONNECTION_TIMEOUT" "${SSH_EXEC[@]}" "$cmd" 2>&1); then
            log_message "DEBUG" "Command executed successfully: $cmd"
            
            # Validate response
            if [[ -n "$output" ]]; then
                log_message "INFO" "Received valid response: $output"
                echo "$output"
                return 0
            else
                log_message "WARN" "iLO4 returned empty output for command: '$cmd'. This is a known iLO4 quirk (especially after reboot). Will retry $empty_output_retries more times."
                local empty_retry=1
                while [[ $empty_retry -le $empty_output_retries ]]; do
                    sleep 2
                    log_message "INFO" "Retrying command due to empty output (attempt $empty_retry/$empty_output_retries)..."
                    output=$(timeout "$CONNECTION_TIMEOUT" "${SSH_EXEC[@]}" "$cmd" 2>&1)
                    if [[ -n "$output" ]]; then
                        log_message "INFO" "Received valid response after retry: $output"
                        echo "$output"
                        return 0
                    fi
                    ((empty_retry++))
                done
                log_message "ERROR" "iLO4 returned empty output for command: '$cmd' after $empty_output_retries retries. Giving up on this command."
            fi
        else
            log_message "ERROR" "Command failed (attempt $((retry + 1))/$COMMAND_RETRIES): $cmd"
            log_message "DEBUG" "Error output: $output"

            # Check for session timeout error
            if [[ "$output" =~ "CLI session timed out" ]]; then
                handle_ssh_timeout
            fi
        fi

        ((retry++))
        if [[ $retry -lt $COMMAND_RETRIES ]]; then
            log_message "DEBUG" "Retrying in 3 seconds..."
            sleep 3
        fi
    done

    log_message "ERROR" "Command failed after $COMMAND_RETRIES attempts: $cmd"
    exit 1
}

# Function to wait for network connectivity
wait_for_network() {
    log_message "INFO" "Waiting for network connectivity..."
    
    for i in $(seq 1 $NETWORK_CHECK_RETRIES); do
        if ping -c 1 -W 5 "$ILO_HOST" >/dev/null 2>&1; then
            log_message "INFO" "iLO host $ILO_HOST is reachable"
            return 0
        fi
        log_message "DEBUG" "Network check $i/$NETWORK_CHECK_RETRIES: Host not reachable"
        sleep "$NETWORK_CHECK_INTERVAL"
    done
    
    log_message "ERROR" "Network connectivity check failed after $NETWORK_CHECK_RETRIES attempts"
    return 1
}

# Function to get PID information from iLO
get_pid_info() {
    log_message "INFO" "Getting PID information from iLO..."
    
    local pids_output
    if pids_output=$(timeout 60 "${SSH_EXEC[@]}" "fan info g" 2>/dev/null); then
        local pids_raw
        pids_raw=$(echo "$pids_output" | grep -oE '\[[^]]+\]' | tr -d '[]' | tr ' ' '\n' | sort -u | grep -v '^$' || true)
        
        if [[ -n "$pids_raw" ]]; then
            log_message "INFO" "Found PIDs: $(echo "$pids_raw" | tr '\n' ' ')"
            echo "$pids_raw"
        else
            log_message "WARN" "No PIDs found in iLO response"
            echo ""
        fi
    else
        log_message "WARN" "Failed to get PID information from iLO"
        echo ""
    fi
}

# Function to handle repeated failures and force exit
handle_repeated_failures() {
    local failure_count="$1"
    local max_failures="$2"
    local failure_reason="$3"

    if [[ "$failure_count" -ge "$max_failures" ]]; then
        log_message "ERROR" "Maximum failure count ($max_failures) reached: $failure_reason"
        log_message "ERROR" "Exiting script to prevent indefinite hanging."
        exit 1
    fi
}

# Updated function to initialize fan control system
initialize_fan_control() {
    log_message "INFO" "Initializing fan control system..."

    # Wait for network connectivity
    log_message "DEBUG" "Checking network connectivity..."
    if ! wait_for_network; then
        log_message "ERROR" "Network connectivity check failed. Ensure the iLO host is reachable at $ILO_HOST."
        exit 1
    fi

    # Test SSH connection
    log_message "DEBUG" "Testing SSH connection to iLO..."
    local ssh_failures=0
    local max_ssh_failures=3
    while ! test_ssh_connection; do
        ((ssh_failures++))
        handle_repeated_failures "$ssh_failures" "$max_ssh_failures" "SSH connection test failed. Verify credentials and network settings."
        sleep 5
    done

    # Set default fan speeds
    log_message "INFO" "Setting default fan speeds to $GLOBAL_MIN_SPEED..."
    for ((i=0; i < FAN_COUNT; i++)); do
        if ! execute_ilo_command "fan p $i min $GLOBAL_MIN_SPEED"; then
            log_message "WARN" "Failed to set default speed for fan $i"
        else
            log_message "DEBUG" "Fan $i default speed set to $GLOBAL_MIN_SPEED"
        fi
        sleep 1
    done

    # Disable specified sensors
    if [[ ${#DISABLED_SENSORS[@]} -gt 0 ]]; then
        log_message "INFO" "Disabling sensors: ${DISABLED_SENSORS[*]}"
        for sensor in "${DISABLED_SENSORS[@]}"; do
            log_message "DEBUG" "Executing command to disable sensor $sensor: fan t $sensor off"
            if output=$(execute_ilo_command "fan t $sensor off"); then
                log_message "DEBUG" "Sensor $sensor disabled successfully. Command output: $output"
            else
                log_message "WARN" "Failed to disable sensor $sensor. Command output: $output"
            fi
            sleep 1
        done
    else
        log_message "INFO" "No sensors to disable. Skipping sensor configuration."
    fi

    log_message "INFO" "Fan control system initialization completed successfully"
}

# Function to get CPU temperature
get_cpu_temp() {
    local cpu_id="$1"
    local temp=0
    
    log_message "DEBUG" "Getting temperature for CPU $cpu_id"
    
    # Method 1: Try using sensors with JSON output
    if command -v sensors &>/dev/null && command -v jq &>/dev/null; then
        local sensors_temp
        sensors_temp=$(sensors -Aj "coretemp-isa-000$cpu_id" 2>/dev/null | \
                      jq -r '.[][] | to_entries[] | select(.key | endswith("input")) | .value' 2>/dev/null | \
                      sort -rn | head -n1 2>/dev/null || echo "")
        
        if [[ "$sensors_temp" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ $(echo "$sensors_temp > 0" | bc -l 2>/dev/null || echo "0") == "1" ]]; then
            temp=${sensors_temp%.*}  # Remove decimal part
            log_message "DEBUG" "CPU $cpu_id temperature from sensors: ${temp}°C"
            echo "$temp"
            return 0
        fi
    fi
    
    # Method 2: Try reading from /sys/class/thermal
    local thermal_zones=("/sys/class/thermal/thermal_zone$cpu_id/temp" "/sys/class/thermal/thermal_zone$((cpu_id + 1))/temp")
    for thermal_zone in "${thermal_zones[@]}"; do
        if [[ -r "$thermal_zone" ]]; then
            local zone_temp
            zone_temp=$(cat "$thermal_zone" 2>/dev/null || echo "0")
            if [[ "$zone_temp" =~ ^[0-9]+$ ]] && [[ $zone_temp -gt 0 ]]; then
                temp=$((zone_temp / 1000))  # Convert millidegrees to degrees
                if [[ $temp -gt 0 && $temp -lt 150 ]]; then  # Sanity check
                    log_message "DEBUG" "CPU $cpu_id temperature from thermal zone: ${temp}°C"
                    echo "$temp"
                    return 0
                fi
            fi
        fi
    done
    
    # Method 3: Try using lm-sensors without JSON
    if command -v sensors &>/dev/null; then
        local sensors_output
        sensors_output=$(sensors 2>/dev/null | grep -i "core\|cpu" | grep -oE '[0-9]+\.[0-9]+°C' | head -n1 | grep -oE '[0-9]+' || echo "")
        if [[ "$sensors_output" =~ ^[0-9]+$ ]] && [[ $sensors_output -gt 0 && $sensors_output -lt 150 ]]; then
            temp="$sensors_output"
            log_message "DEBUG" "CPU $cpu_id temperature from sensors (fallback): ${temp}°C"
            echo "$temp"
            return 0
        fi
    fi
    
    # If all methods fail, return a safe default
    temp=45  # Safe default temperature
    log_message "WARN" "Unable to read CPU $cpu_id temperature, using default: ${temp}°C"
    echo "$temp"
    return 1
}

# Function to determine fan speed based on temperature
get_fan_speed_for_temp() {
    local temp="$1"
    local speed="$TEMP_THRESHOLD_DEFAULT"  # Default speed
    
    log_message "DEBUG" "Determining fan speed for temperature: ${temp}°C"
    
    # Check temperature thresholds using configurable TEMP_STEPS array
    # Sort temperature steps in descending order and check each one
    local sorted_steps=($(printf '%s\n' "${TEMP_STEPS[@]}" | sort -nr))
    
    for step in "${sorted_steps[@]}"; do
        if [[ $temp -ge $step ]]; then
            # Get the corresponding threshold variable
            local threshold_var="TEMP_THRESHOLD_${step}"
            if [[ -n "${!threshold_var}" ]]; then
                speed="${!threshold_var}"
                log_message "DEBUG" "Temperature ${temp}°C matched threshold ≥${step}°C, fan speed: ${speed}"
                break
            fi
        fi
    done
    
    # If no threshold matched, use default
    if [[ $speed == "$TEMP_THRESHOLD_DEFAULT" ]]; then
        log_message "DEBUG" "Using default temperature mode for ${temp}°C"
    fi
    
    # Emergency protection
    if [[ $temp -ge $MAX_TEMP_CPU ]]; then
        speed="$EMERGENCY_SPEED"
        log_message "ERROR" "EMERGENCY: CPU temperature ${temp}°C ≥ ${MAX_TEMP_CPU}°C! Setting maximum fan speed!"
    fi
    
    log_message "DEBUG" "Selected fan speed: $speed for ${temp}°C"
    echo "$speed"
}

# Function to set fan speeds for a CPU
set_cpu_fan_speeds() {
    local cpu_num="$1"
    local temp="$2"
    local speed="$3"
    local fans_array_name="CPU${cpu_num}_FANS[@]"
    local fans=("${!fans_array_name}")
    
    log_message "INFO" "Setting CPU${cpu_num} fans (temp: ${temp}°C, speed: ${speed})"
    
    local success_count=0
    local total_fans=${#fans[@]}
    
    for fan in "${fans[@]}"; do
        log_message "INFO" "Setting Fan $fan to speed $speed (CPU$cpu_num, temp: $temp°C)"
        if execute_ilo_command "fan p $fan max $speed"; then
            log_message "DEBUG" "Fan $fan set to speed $speed"
            ((success_count++))
        else
            log_message "ERROR" "Failed to set Fan $fan speed"
        fi
        sleep 0.5  # Small delay between fan commands
    done
    
    if [[ $success_count -eq $total_fans ]]; then
        log_message "INFO" "All CPU${cpu_num} fans ($success_count/$total_fans) configured successfully"
    else
        log_message "WARN" "Only $success_count/$total_fans CPU${cpu_num} fans configured successfully"
    fi
    
    return 0
}

# Function to handle emergency situations
handle_emergency() {
    local reason="$1"
    log_message "ERROR" "EMERGENCY SITUATION: $reason"
    log_message "ERROR" "Setting all fans to maximum speed ($EMERGENCY_SPEED)"
    
    # Set all fans to maximum speed
    for ((i=0; i < FAN_COUNT; i++)); do
        if ! execute_ilo_command "fan p $i max $EMERGENCY_SPEED"; then
            log_message "ERROR" "Failed to set emergency speed for fan $i"
        fi
    done
    
    # Log the emergency and continue monitoring
    log_message "ERROR" "Emergency fan speeds set. Continuing monitoring..."
}

# Function to monitor temperatures and adjust fans
monitor_and_control_fans() {
    log_message "INFO" "Starting dynamic fan control monitoring (interval: ${MONITORING_INTERVAL}s)"
    
    local consecutive_errors=0
    local max_consecutive_errors=5
    local last_cpu1_temp=0
    local last_cpu2_temp=0
    local cycle_count=0
    
    while true; do
        ((cycle_count++))
        log_message "DEBUG" "Starting monitoring cycle $cycle_count"
        
        # Get CPU temperatures
        local cpu1_temp cpu2_temp
        cpu1_temp=$(get_cpu_temp 0) || { log_message "ERROR" "get_cpu_temp 0 failed"; cpu1_temp=0; }
        cpu2_temp=$(get_cpu_temp 1) || { log_message "ERROR" "get_cpu_temp 1 failed"; cpu2_temp=0; }
        
        # Validate temperatures
        if [[ $cpu1_temp -eq 0 && $cpu2_temp -eq 0 ]]; then
            ((consecutive_errors++))
            log_message "ERROR" "Both CPU temperatures read as 0°C (error count: $consecutive_errors)"
            
            if [[ $consecutive_errors -ge $max_consecutive_errors ]]; then
                handle_emergency "Multiple temperature reading failures"
                consecutive_errors=0  # Reset counter after emergency action
            fi
            
            # Use last known good temperatures if available
            if [[ $last_cpu1_temp -gt 0 ]]; then
                cpu1_temp=$last_cpu1_temp
                log_message "WARN" "Using last known CPU1 temperature: ${cpu1_temp}°C"
            fi
            if [[ $last_cpu2_temp -gt 0 ]]; then
                cpu2_temp=$last_cpu2_temp
                log_message "WARN" "Using last known CPU2 temperature: ${cpu2_temp}°C"
            fi
        else
            consecutive_errors=0  # Reset error counter on successful reading
            last_cpu1_temp=$cpu1_temp
            last_cpu2_temp=$cpu2_temp
        fi
        
        # Emergency temperature check
        if [[ $cpu1_temp -ge $MAX_TEMP_CPU ]] || [[ $cpu2_temp -ge $MAX_TEMP_CPU ]]; then
            handle_emergency "CPU temperature exceeds ${MAX_TEMP_CPU}°C (CPU1: ${cpu1_temp}°C, CPU2: ${cpu2_temp}°C)"
        fi
        
        log_message "INFO" "==============================================="
        log_message "INFO" "Cycle $cycle_count: CPU1: ${cpu1_temp}°C, CPU2: ${cpu2_temp}°C"
        log_message "INFO" "==============================================="
        
        # Determine fan speeds based on temperatures
        local cpu1_speed cpu2_speed
        cpu1_speed=$(get_fan_speed_for_temp "$cpu1_temp") || { log_message "ERROR" "get_fan_speed_for_temp for CPU1 failed"; cpu1_speed=$GLOBAL_MIN_SPEED; }
        cpu2_speed=$(get_fan_speed_for_temp "$cpu2_temp") || { log_message "ERROR" "get_fan_speed_for_temp for CPU2 failed"; cpu2_speed=$GLOBAL_MIN_SPEED; }
        
        # Set fan speeds for each CPU
        if ! set_cpu_fan_speeds 1 "$cpu1_temp" "$cpu1_speed"; then
            log_message "ERROR" "set_cpu_fan_speeds 1 failed"
        fi
        if ! set_cpu_fan_speeds 2 "$cpu2_temp" "$cpu2_speed"; then
            log_message "ERROR" "set_cpu_fan_speeds 2 failed"
        fi
        
        log_message "INFO" "Fan control cycle $cycle_count completed. Sleeping for ${MONITORING_INTERVAL}s..."
        
        # Periodic connection health check (every 10 cycles)
        if [[ $((cycle_count % 10)) -eq 0 ]]; then
            log_message "DEBUG" "Performing periodic connection health check..."
            if ! test_ssh_connection; then
                log_message "WARN" "SSH connection health check failed"
            fi
        fi
        
        sleep "$MONITORING_INTERVAL"
    done
}

# Function to handle script cleanup
cleanup() {
    log_message "INFO" "Cleaning up and exiting..."
    exit 0
}

# Set up signal traps
trap cleanup SIGTERM SIGINT

# Dependency check function
check_dependencies() {
    local missing=()
    local required=("ssh" "timeout" "ping" "grep" "awk" "sort" "tr" "head" "sleep")
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        required+=("sensors")
    fi
    for cmd in "${required[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_message "ERROR" "Missing required dependencies: ${missing[*]}"
        log_message "ERROR" "Please install the missing commands and restart the service."
        exit 1
    fi
}

# Main execution flow
main() {
    check_dependencies
    # Initialize the fan control system
    if ! initialize_fan_control; then
        log_message "ERROR" "Fan control initialization failed"
        exit 1
    fi
    # Start dynamic fan control if enabled
    if [[ "$ENABLE_DYNAMIC_CONTROL" == "true" ]]; then
        log_message "INFO" "Dynamic fan control is enabled. Starting monitoring..."
        (
            trap 'log_message "ERROR" "Unexpected error or exit in monitoring loop (cycle $cycle_count). Service will attempt to continue."' ERR
            monitor_and_control_fans
        )
        local monitor_status=$?
        if [[ $monitor_status -ne 0 ]]; then
            log_message "ERROR" "Monitoring loop exited unexpectedly with status $monitor_status. Restarting loop..."
            sleep 5
            exec "$0" "$@"
        fi
    else
        log_message "INFO" "Dynamic fan control is disabled. Initial setup complete."
        log_message "INFO" "To enable dynamic control, set ENABLE_DYNAMIC_CONTROL=true in configuration"
    fi
    
    log_message "INFO" "Script execution completed."
}

# Execute main function
main "$@"
