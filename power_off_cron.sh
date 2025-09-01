#!/bin/bash

# Configuration
POOL_NAMES="poola poolb"    # LIST ALL YOUR POOLS HERE separated by spaces
CHECK_INTERVAL=30         # Time in seconds between I/O checks
MAX_CHECKS=120            # Max checks before timeout (120 * 30s = 60 minutes)
LOG_FILE="/tmp/power_log" # Path to the log file

# Function to write a message with a timestamp to the log file
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Start a fresh log for this session
echo "--- Nightly Shutdown Attempt Started ---" > "$LOG_FILE"
log_message "Script started. Waiting for all pools to become idle."
log_message "Monitoring pools: $POOL_NAMES"

# Function to get current disk I/O for a specific pool in KB/s
get_pool_io() {
    local pool=$1
    zpool iostat -y "$pool" 2 1 | tail -n 1 | awk '{print $4 + $5}'
}

# Function to check all pools for activity
check_all_pools_idle() {
    local all_idle=true
    local current_io
    
    for pool in $POOL_NAMES; do
        current_io=$(get_pool_io "$pool")
        # Check if I/O is effectively zero (less than 1 KB/s)
        if (( $(echo "$current_io >= 1" | bc -l) )); then
            log_message "INFO: Pool '$pool' has activity: ${current_io} KB/s"
            all_idle=false
        fi
    done
    
    echo "$all_idle"
}

for ((count=1; count<=MAX_CHECKS; count++)); do
    # Check if all pools are idle
    if [ "$(check_all_pools_idle)" = "true" ]; then
        log_message "SUCCESS: All pools are idle. Proceeding with shutdown."
        shutdown -h now
        exit 0 # Script ends here on successful shutdown
    else
        log_message "INFO: Check $count/$MAX_CHECKS - Activity detected. Retrying in ${CHECK_INTERVAL}s."
        sleep $CHECK_INTERVAL
    fi
done

# If the script reaches here, it timed out
log_message "ERROR: Shutdown timed out after $((MAX_CHECKS * CHECK_INTERVAL / 60)) minutes. Aborting shutdown for safety."
log_message "Some pools may still be active. Please investigate manually."
exit 1
