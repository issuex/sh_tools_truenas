#!/bin/sh

# - no netdav support
# - minimal process call for use in cron task

led_exec="/mnt/your_pool/ugreen_leds_cli"
led_status_file="/tmp/led_status_old"

# - map your hdd with serial
hdd_sn="
01 WD-XXX
02 WD-YYY
03 WD-ZZZ
04 WD-AAA
"

set_white_dim() {
    $led_exec $1 -on -color 200 255 255 -brightness 5
}
set_white() {
    $led_exec $1 -on -color 200 255 255 -brightness 15
}
set_green() {
    $led_exec $1 -on -color 48 207 48 -brightness 25
}
set_blue() {
    $led_exec $1 -on -color 0 60 255 -brightness 45
}
set_yellow() {
    $led_exec $1 -on -color 255 234 0 -brightness 10
}
set_blink() {
    $led_exec $1 -on -color 255 191 0 -brightness 80 -blink 500 500 
}
set_off() {
    $led_exec $1 -off
}

set_hdd_led() {
    local num=$1
    local status=$2
    if [ "$status" = "ONLINE" ]; then
        set_white disk${num}
    elif [ "$status" = "AVAIL" ]; then
        set_yellow disk${num}
    else
        # - etc fail case : UNKNOWN UNAVAIL FAULTED DEGRADED
        set_blink disk${num}
    fi
}

# START

disk_info=$(lsblk -d -o NAME,SERIAL)
disk_map=$(echo "$hdd_sn" | awk -v disks="$disk_info" '
NF >= 2 {  # Only process lines with at least 2 fields
    number = $1 + 0  # Convert "01"
    serial = $2
    device = "unknown"
    
    # Search for the serial in disk_info
    split(disks, all_disks, "\n")
    for (i in all_disks) {
        split(all_disks[i], parts, " ")
        if (parts[2] == serial) {
            device = parts[1]
            break
        }
    }
    
    print number " " serial " " device "\n"
}')
# <num> <sn> <sd*>

pool_status=$(zpool status -PL)
disk_status=$(echo "$disk_map" | awk -v pools="$pool_status" '
NF >= 2 {
    number = $1
    serial = $2
    device = $3
    
    # Search for the serial in disk_info
    split(pools, all_disks, "\n")
    for (i in all_disks) {
        if (device == "unknown") {
            status = "UNKNOWN"
        } else {
            split(all_disks[i], parts, " ")
            if (parts[1] ~ device) {
                status = parts[2]
                break
            }
        }
    }
    
    print number " " serial " " device " " status
}')
# <num> <sn> <sd*> <status>

# CHECK-BOOT
if [ -f "$led_status_file" ]; then
    echo  "found led boot"
else
    echo "not found led boot > run init"
    modprobe i2c-dev

    set_white_dim power
    set_green netdev

    while read -r num sn sd status; do
        set_hdd_led "$num" "$status"
    done <<EOF
$disk_status
EOF

    printf "%s\n" "$disk_status" > $led_status_file
fi

# COMPARE & APPLY
disk_status_old=$(cat $led_status_file)
led_change=0
while read -r a1 b1 c1 d1 && read -r num sn sd status <&3; do
    if [ "$d1" = "$status" ]; then
        echo "disk${a1} same status: $status"
    else
        echo "disk${a1} status change: $d1 > $status"
        led_change=1
        set_hdd_led "$num" "$status"
    fi
done <<EOF 3<<EOF2
$disk_status_old
EOF
$disk_status
EOF2

# FINAL
if [ "$led_change" -eq 1 ]; then
    printf "%s\n" "$disk_status" > $led_status_file
fi
