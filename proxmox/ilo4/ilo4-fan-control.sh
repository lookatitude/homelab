#!/bin/bash

# === CONFIGURATION ===
ILO_HOST="<server ip or hostname>"  # iLO IP or hostname
ILO_USER="Administrator"

USE_SSH_PASS=true              # Set to false to use SSH key auth
ILO_PASS="<password>"           # Required only if USE_SSH_PASS=true

FAN_COUNT=6                    # Number of fans (fan 0 to FAN_COUNT-1)
GLOBAL_MIN_SPEED=60           # Minimum fan speed
PID_MIN_LOW=1600              # Minimum low for all PIDs
DISABLED_SENSORS=(07FB00 35 38)  # Sensors to turn off
# ========================

echo "LOGGING IN to iLO..."

# Build the SSH command options (safe legacy ciphers for iLO4)
SSH_OPTS=(
  -o StrictHostKeyChecking=no
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
    SSH_EXEC=(sshpass -p "$ILO_PASS" ssh -tt "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
else
    SSH_EXEC=(ssh -tt "${SSH_OPTS[@]}" "$ILO_USER@$ILO_HOST")
fi

echo "SSH command: ${SSH_EXEC[*]}"

# --- Step 1: Get PIDs remotely ---
PIDS_RAW=$("${SSH_EXEC[@]}" fan info g | grep -oE '\[[^]]+\]' | tr -d '[]' | tr ' ' '\n' | sort -u | grep -v '^$')

# --- Step 2: Build commands to send ---
REMOTE_CMDS=""

for ((i=0; i < FAN_COUNT; i++)); do
    REMOTE_CMDS+="fan p $i min $GLOBAL_MIN_SPEED"$'\n'
done

while IFS= read -r pid; do
    REMOTE_CMDS+="fan pid $pid lo $PID_MIN_LOW"$'\n'
done <<< "$PIDS_RAW"

for sensor in "${DISABLED_SENSORS[@]}"; do
    REMOTE_CMDS+="fan t $sensor off"$'\n'
done

REMOTE_CMDS+="exit"$'\n'

# --- Step 3: Run the commands remotely ---
echo "Running fan configuration commands on iLO..."

"${SSH_EXEC[@]}" <<EOF
$REMOTE_CMDS
EOF

echo "Done."
