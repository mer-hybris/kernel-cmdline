#!/bin/bash

SCRIPT_VERSION=1.0.0
PRINT_RED='\033[0;31m'
PRINT_GREEN='\033[0;32m'
PRINT_NC='\033[0m'

packbootimg_bin="/usr/libexec/kernel-cmdline/mkbootimg"
unpackbootimg_bin="/usr/libexec/kernel-cmdline/unpackbootimg"

selinux_config_file="/etc/selinux/config"
device_info_file="/var/lib/flash-partition/device-info"
tmp_path="/tmp/cmdline.$$"
tmp_image_a="$tmp_path/boot_a.img"
tmp_image_b="$tmp_path/boot_b.img"
res_image_a="$tmp_path/boot_a-modified.img"
res_image_b="$tmp_path/boot_b-modified.img"
tempfs_size="512m"

only_print=0
force_yes=0
quiet_mode=0

declare -a modify_vars
declare -a modify_vals
declare -a modify_vars_full
declare -a remove_vars
declare -a var_set

boot_device_a=
boot_device_b=

options=
cmdline_a=
cmdline_b=
new_cmdline=

##########################################################################
# Helper functions

print_help() {
    echo "$(basename $0) v$SCRIPT_VERSION"
    echo ""
    echo "  Modify kernel cmdline argument."
    echo ""
    echo "     --pack       Alternative location for packbootimg binary."
    echo "     --unpack     Alternative location for unpackbootimg binary."
    echo "  -d --device     Boot device location."
    echo "     --selinux    Set SELinux mode (disabled/permissive/enforcing or restore)."
    echo "  -p --print      Only print current command line."
    echo "     --cmdline    Set full kernel cmdline."
    echo "  -s --set        Set argument to new value (eg. selinux=1)."
    echo "  -r --remove     Remove argument."
    echo "  -y --yes        Commit changes without question."
    echo "     --quiet      Print only error messages."
    echo "     --verbose    Print more verbose output."
    echo "     --help       This help."
    echo ""
}

print_version() {
    echo "v$SCRIPT_VERSION"
}

cleanup() {
    if [ -d "$tmp_path" ]; then
        umount "$tmp_path"
        rmdir "$tmp_path"
    fi
}

log_debug() {
    if [ -n "$DEBUG" ]; then
        echo "$@"
    fi
}

log_normal() {
    if [ $quiet_mode -eq 0 ]; then
        echo "$@"
    fi
}

log_green() {
    log_normal -e -n "$PRINT_GREEN$@$PRINT_NC"
}

log_red() {
    log_normal -e -n "$PRINT_RED$@$PRINT_NC"
}

log_always() {
    echo "$@"
}

log_error() {
    echo "$@" >&2
}

detect_boot_device() {
    local partition_name=
    local boot_partition=

    if [ -f "$device_info_file" ]; then
        log_debug "Device info file found in $device_info_file"
        source "$device_info_file"
        if [ -z "$PART_I" ]; then
            echo "Invalid device info file $device_info_file"
            exit 1
        fi
        for i in $PART_I; do
            eval partition_name="\${PART_$i}"
            eval boot_partition="/dev/\${PART_REAL_$i}"
            log_debug "Partition $partition_name: $boot_partition"
            case $partition_name in
                boot)   boot_device_a="$boot_partition"     ;;
                boot_a) boot_device_a="$boot_partition"     ;;
                boot_b) boot_device_b="$boot_partition"     ;;
            esac
        done
        if [ -n "$boot_device_b" ]; then
            if [[ ! -b "$boot_device_a" || ! -b "$boot_device_b" ]]; then
                log_error "Both boot_a and boot_b partitions defined in $device_info_file but one is not block device!"
                return 1
            fi
        fi
        if [ ! -b "$boot_device_a" ]; then
            log_error "Boot partition defined in $device_info_file but it is not block device!"
            return 1
        fi
        return 0
    fi

    log_debug "Try to detect boot partition(s)..."

    boot_device_a="$(ls -1 /dev/block/platform/*/by-name/boot 2>/dev/null)"
    if [ -b "$boot_device_a" ]; then
        log_debug "Partition boot: $boot_device_a"
        return 0
    fi

    boot_device_a="$(ls -1 /dev/block/platform/*/by-name/boot_a 2>/dev/null)"
    boot_device_b="$(ls -1 /dev/block/platform/*/by-name/boot_b 2>/dev/null)"
    if [[ -b "$boot_device_a" && -b "$boot_device_b" ]]; then
        log_debug "Partition boot_a: $boot_device_a"
        log_debug "Partition boot_b: $boot_device_b"
        return 0
    fi

    return 1
}

unpack_image() {
    log_debug "Unpacking $1..."
    $unpackbootimg_bin -i "$1" -o "$tmp_path" 1>/dev/null
    if [ $? -ne 0 ]; then
        echo "Failed to unpack boot image."
        exit 1
    fi
}

extend_options() {
    local file="$1-$2"
    shift
    if [ $# -gt 1 ]; then
        shift
    fi
    local arg="$1"

    if [ -f "$file" ]; then
        local val="$(cat "$file")"
        if [ -n "$val" ]; then
            log_debug "Append --$arg $val"
            options="$options --$arg $val"
        fi
    fi
}

extend_options_file() {
    local file="$1-$2"
    shift
    if [ $# -gt 1 ]; then
        shift
    fi
    local arg="$1"

    if [ -f "$file" ]; then
        log_debug "Append --$arg $file"
        options="$options --$arg $file"
    fi
}

pack_image() {
    local base="$1"
    shift
    local out="$1"
    shift
    local cmdline="$@"
    log_debug "Pack image to $out..."

    options="--kernel $base-zImage"
    #                             | filename      | argument if not same as filename
    extend_options          $base   base
    extend_options          $base   board
    extend_options          $base   pagesize
    extend_options          $base   hash
    extend_options          $base   kerneloff       kernel_offset
    extend_options          $base   ramdiskoff      ramdisk_offset
    extend_options          $base   secondoff       second_offset
    extend_options          $base   tagsoff         tags_offset
    extend_options          $base   dtboff          dtb_offset
    extend_options          $base   osversion       os_version
    extend_options          $base   oslevel         os_patch_level
    extend_options          $base   headerversion   header_version
    extend_options_file     $base   ramdisk.gz      ramdisk
    extend_options_file     $base   second
    extend_options_file     $base   dtb
    extend_options_file     $base   dt
    extend_options_file     $base   recoverydtbo    recovery_dtbo

    log_debug "Pack new image with: $packbootimg_bin $options --cmdline \"$cmdline\""
    $packbootimg_bin $options --cmdline "$cmdline" -o $out
    if [ $? -ne 0 ]; then
        log_error "Failed to generate new boot image."
        exit 1
    fi
}

read_from_emmc() {
    log_debug "Read from $1..."
    dd status=noxfer if="$1" of="$2" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to read current boot image from $1"
        exit 1
    fi
}

write_to_emmc() {
    log_normal "Writing to $2..."
    dd status=noxfer if="$1" of="$2" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to write $1 to device $2" >&2
        exit 3
    fi
}

add_modify_var() {
    modify_vars+=("$(echo $1 | cut -d'=' -f1)")
    var_set+=("0")
    modify_vars_full+=("$1")
    if [ -n "$(echo $1 | grep -e '=')" ]; then
        modify_vals+=("$(echo $1 | cut -d'=' -f2-)")
    else
        modify_vals+=("")
    fi
}

set_selinux_vars() {
    local mode=$1

    if [ "$mode" == "restore" ]; then
        if [ -f "$selinux_config_file" ]; then
            source "$selinux_config_file"
            if [ -z "$SELINUX" ]; then
                log_error "Invalid SELinux configuration."
                exit 1
            fi
            mode=$SELINUX
        else
            # No need to do anything as SELinux configuration
            # doesn't exist.
            exit 0
        fi
    fi

    local selinux_var=0
    local enforce_var=0

    case $mode in
        disabled) ;;
        permissive) selinux_var=1                   ;;
        enforcing)  selinux_var=1 ; enforce_var=1   ;;
        *)
            log_error "Unknown argument to selinux (needs to be disabled/permissive/enforcing or restore)."
            exit 1
            ;;
    esac

    add_modify_var "selinux=$selinux_var"
    add_modify_var "enforcing=$enforce_var"
}

##########################################################################
# Read command line arguments

while [ $# -gt 0 ]; do
    case $1 in
        --help)
            print_help
            exit 0
            ;;
        --version)
            print_version
            exit 0
            ;;
        --pack)
            shift
            packbootimg_bin="$1"
            if [[ -d "$packbootimg_bin" || ! -x "$packbootimg_bin" ]]; then
                log_error "$packbootimg_bin is not executable file."
                exit 1
            fi
            ;;
        --unpack)
            shift
            unpackbootimg_bin="$1"
            if [[ -d "$unpackbootimg_bin" || ! -x "$unpackbootimg_bin" ]]; then
                log_error "$unpackbootimg_bin is not executable file."
                exit 1
            fi
            ;;
        -p|--print)
            only_print=1
            ;;
        -y|--yes)
            force_yes=1
            ;;
        --verbose)
            DEBUG=1
            ;;
        --quiet)
            quiet_mode=1
            ;;
        -d|--device)
            shift
            boot_device_a="$1"
            if [ ! -b "$boot_device_a" ]; then
                log_error "Device $boot_device_a doesn't exist or isn't block device."
                exit 1
            fi
            ;;
        --cmdline)
            shift
            new_cmdline="$1"
            ;;
        -s|--set)
            shift
            add_modify_var "$1"
            ;;
        -r|--remove)
            shift
            remove_vars+=("$1")
            ;;
        --selinux)
            shift
            set_selinux_vars $1
            ;;
        *)
            print_help
            exit 1
    esac
    shift
done

##########################################################################
# Check for root access and for needed dependencies

if [ $UID -ne 0 ]; then
    echo "This script needs root access."
    exit 1
fi

if [ ! -x "$packbootimg_bin" ]; then
    log_error "Could not find mkbootimg binary."
    exit 1
fi

if [ ! -x "$unpackbootimg_bin" ]; then
    log_error "Could not find mkbootimg binary."
    exit 1
fi

##########################################################################
# Detect boot partition

if [ -z "$boot_device_a" ]; then
    if ! detect_boot_device; then
        log_error "Could not detect boot partition."
        exit 1
    fi
fi

##########################################################################
# Create temporary filesystem for all operations

trap cleanup EXIT

log_debug "Mount tmpfs ($tempfs_size) to $tmp_path"
mkdir -p "$tmp_path"
mount -t tmpfs -o size=$tempfs_size cmdline.$$ "$tmp_path"
if [ $? -ne 0 ]; then
    log_error "Failed to create temporary directory."
    rmdir "$tmp_path"
    exit 1
fi

##########################################################################
# Read boot partition(s), (and in case of boot_a and boot_b make sure they
# are identical)

read_from_emmc "$boot_device_a" "$tmp_image_a"
unpack_image "$tmp_image_a"
cmdline_a="$(cat "$tmp_image_a-cmdline")"

if [ -n "$boot_device_b" ]; then
    read_from_emmc "$boot_device_b" "$tmp_image_b"
    unpack_image "$tmp_image_b"
    cmdline_b="$(cat "$tmp_image_b-cmdline")"

    if [ "$cmdline_a" != "$cmdline_b" ]; then
        log_error "boot_a and boot_b command lines differ!"
        log_error "boot_a: $cmdline_a"
        log_error "boot_b: $cmdline_b"
        exit 1
    fi
fi

if [ $only_print -eq 1 ]; then
    log_always "$cmdline_a"
    exit 0
fi

##########################################################################
# Construct new cmdline argument

log_debug "old cmdline: $cmdline_a"

if [ -n "$new_cmdline" ]; then
    log_normal "new cmdline: $new_cmdline"
else
    # Construct new modified command line
    space=""
    log_normal -n "new cmdline: "
    for entry in $cmdline_a; do
        var="$(echo $entry | cut -d'=' -f1)"
        val="$(echo $entry | cut -d'=' -f2-)"
        modified=0

        i=0
        for mod in "${modify_vars[@]}"; do
            if [ "$var" == "$mod" ]; then
                modify_var_val="${modify_vals[$i]}"
                if [ "$modify_var_val" != "$val" ]; then
                    new_cmdline="$new_cmdline$space${modify_vars_full[$i]}"
                    log_green "$space${modify_vars_full[$i]}"
                    modified=1
                fi
                var_set[$i]="1"
            fi
            ((i++))
        done

        for rem in "${remove_vars[@]}"; do
            if [ "$var" == "$rem" ]; then
                modified=1
                break
            fi
        done

        if [ $modified -eq 0 ]; then
            new_cmdline="$new_cmdline$space$entry"
            log_normal -n "$space$entry"
        fi

        if [ -n "$new_cmdline" ]; then
            space=" "
        fi
    done

    i=0
    for vset in "${var_set[@]}"; do
        if [ "$vset" == "1" ]; then
            ((i++))
            continue
        fi
        new_cmdline="$new_cmdline$space${modify_vars_full[$i]}"
        log_green "$space${modify_vars_full[$i]}"
        space=" "
        ((i++))
    done

    log_normal ""
fi

if [ "$cmdline_a" == "$new_cmdline" ]; then
    log_normal "No changes to current kernel cmdline."
    exit 0
fi

##########################################################################
# Pack modified image(s)

pack_image "$tmp_image_a" "$res_image_a" "$new_cmdline"
if [ -n "$boot_device_b" ]; then
    pack_image "$tmp_image_b" "$res_image_b" "$new_cmdline"
fi

if [ $force_yes -eq 1 ]; then
    commit="y"
else
    log_always -n "Commit to device? [y\\N] "
    read commit
    commit="$(echo $commit | tr '[A-Z]' '[a-z]')"
fi

##########################################################################
# Write modified image(s) to boot partition(s)

if [ "$commit" == "y" ]; then
    write_to_emmc "$res_image_a" "$boot_device_a"
    if [ -n "$boot_device_b" ]; then
        write_to_emmc "$res_image_b" "$boot_device_b"
    fi
fi
