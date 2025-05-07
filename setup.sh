#!/bin/bash 

# Exit immediately if a command exits with a non-zero status.
set -euo pipefail
cd ~
# --- Configuration ---
readonly base_url="https://downloads.raspberrypi.com/raspios_lite_arm64/images/"
readonly image_prefix="raspios_lite_arm64"
# The part of the filename *after* the date for the compressed image
readonly compressed_suffix="-raspios-bookworm-arm64-lite.img.xz"
# The part of the filename *after* the date for the decompressed image
readonly image_suffix="-raspios-bookworm-arm64-lite.img"
# Hardcoded user:password hash (user: pi, pass: raspberry)
readonly user_conf_line='pi:$6$rBoByrWRKMY1EHFy$ho.LISnfm83CLBWBE/yqJ6Lq1TinRlxw/ImMTPcvcMuUfhQYcMmFnpFXUPowjy2br1NA0IACwF9JKugSNuHoe0'

# Specific override for the 2025-05-07 directory due to filename mismatch
readonly problematic_dir="raspios_lite_arm64-2025-05-07/"
readonly override_filename="2025-05-06-raspios-bookworm-arm64-lite.img.xz"
# ---

# --- Helper Functions ---
log() {
    echo "--> $*"
}

error() {
    echo "Error: $*" >&2
    exit 1
}

check_deps() {
    local missing=0
    # Updated dependencies for mtools method
    for cmd in curl grep sort tail xz stat fdisk awk mcopy tee touch mktemp qemu-img; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "Error: Required command '$cmd' not found." >&2
            missing=1
        fi
    done
    if [[ "$missing" -eq 1 ]]; then
        exit 1
    fi
}
# ---

# --- Main Script ---
check_deps

log "Finding the latest Raspberry Pi OS Lite (arm64) image directory..."

newest_dir=$(
    curl -sL "$base_url" |
    grep -oP "${image_prefix}-\d{4}-\d{2}-\d{2}/" |
    sort |
    tail -n 1
)

if [[ -z "$newest_dir" ]]; then
    error "Could not find any matching image directories at $base_url"
fi
log "Latest directory found: $newest_dir"

# --- Logic to handle the potential filename mismatch ---
compressed_filename="" # Initialize variable

# Check if the latest directory is the one with the known issue
if [[ "$newest_dir" == "$problematic_dir" ]]; then
    log "Detected known problematic directory '$newest_dir'. Using hardcoded filename override."
    compressed_filename="$override_filename"
    # Extract date part from the override filename for the decompressed image name
    date_part=$(echo "$compressed_filename" | grep -oP '\d{4}-\d{2}-\d{2}')
     if [[ -z "$date_part" ]]; then
        error "Could not extract date from override filename '$compressed_filename'."
    fi
else
    log "Latest directory is standard. Checking directory contents for filename..."
    # Construct the URL for the directory listing
    directory_url="${base_url}${newest_dir}"

    # List files in the directory and look for the compressed image
    compressed_filename=$(
        curl -sL "$directory_url" |
        grep -oP '\d{4}-\d{2}-\d{2}'"${compressed_suffix}" |
        tail -n 1 # In case there are multiple, take the last one (usually the latest)
    )

    if [[ -z "$compressed_filename" ]]; then
        # Fallback: If we couldn't find a filename with the expected pattern,
        # try to derive it from the directory date as a last resort.
        log "Could not find compressed image filename with date prefix in directory listing. Falling back to directory date."
        date_part=$(echo "$newest_dir" | grep -oP '\d{4}-\d{2}-\d{2}')
        if [[ -z "$date_part" ]]; then
            error "Could not extract date from directory name '$newest_dir'."
        fi
        compressed_filename="${date_part}${compressed_suffix}"
        log "Constructed filename from directory date: $compressed_filename"
    else
        log "Found compressed image filename: $compressed_filename"
        # Extract the date part from the found filename
        date_part=$(echo "$compressed_filename" | grep -oP '\d{4}-\d{2}-\d{2}')
        if [[ -z "$date_part" ]]; then
           # This shouldn't happen if the filename pattern matched, but for safety:
           log "Warning: Could not extract date from found filename '$compressed_filename'."
           # Still attempt to proceed, the download might still work.
        fi
    fi
fi
# --- End of filename mismatch handling ---

# Ensure we have a date_part defined for the decompressed filename
if [[ -z "$date_part" ]]; then
    # As a final fallback, try to get the date from the *found* compressed filename
    # This covers the override case where date_part was extracted from override_filename
    date_part=$(echo "$compressed_filename" | grep -oP '\d{4}-\d{2}-\d{2}')
    if [[ -z "$date_part" ]]; then
        error "Could not determine date part for the decompressed filename."
    fi
fi

image_filename="${date_part}${image_suffix}"
download_url="${base_url}${newest_dir}${compressed_filename}" # Use the correct directory_url and determined compressed_filename

log "Filename to download: $compressed_filename"
log "Image filename after decompression will be: $image_filename"
log "Download URL: $download_url"

if [[ ! -f "$compressed_filename" ]]; then
    log "Starting download..."
    # Use -C - to resume downloads, but it might not work with all servers or file types.
    # For simplicity, we'll stick to clean downloads or skip if present.
    if ! curl -fSL -o "$compressed_filename" "$download_url"; then
        rm -f "$compressed_filename" 2>/dev/null
        error "Download failed from $download_url."
    fi
    log "Download complete: $compressed_filename"
else
    log "Compressed file '$compressed_filename' already exists. Skipping download."
fi

if [[ ! -f "$image_filename" ]]; then
    log "Decompressing '$compressed_filename'..."
    if ! xz -d "$compressed_filename"; then
        error "Decompression failed for '$compressed_filename'."
    fi
    if [[ ! -f "$image_filename" ]]; then
        error "Decompression finished, but expected file '$image_filename' not found."
    fi
    log "Decompression complete: '$image_filename' created."
else
    log "Decompressed file '$image_filename' already exists. Skipping decompression."
fi

# --- MTOOLS Setup ---
log "Determining boot partition offset for mtools..."
# Use LC_ALL=C for consistent fdisk output
fdisk_output=$(LC_ALL=C fdisk -lu "$image_filename")

# Try to get sector size from "Units: sectors of 1 * SIZE = SIZE bytes"
sector_size_val=$(echo "$fdisk_output" | awk '
    /Units: sectors of/ {
        for (i=1; i<=NF; i++) {
            if ($i == "*" && $(i+1) ~ /^[0-9]+$/) {
                print $(i+1);
                exit;
            }
        }
    }
')
# Fallback for "Sector size (logical/physical): SIZE bytes / SIZE bytes"
if [[ -z "$sector_size_val" ]]; then
    sector_size_val=$(echo "$fdisk_output" | awk '
        /Sector size \(logical\/physical\):/ {
            if ($4 ~ /^[0-9]+$/) { print $4; exit; }
        }
    ')
fi

if [[ -z "$sector_size_val" ]] || ! [[ "$sector_size_val" =~ ^[0-9]+$ ]]; then
    error "Could not determine sector size for '$image_filename' from fdisk output:\n$fdisk_output"
fi
readonly sector_size="$sector_size_val"
log "Determined sector size: $sector_size bytes"

# Find the start sector of the first partition that is FAT32.
start_sector_val=$(echo "$fdisk_output" | awk -v image_basename="${image_filename##*/}" '
    ($1 ~ image_basename || $1 ~ /[0-9]$/ || $1 ~ /\*$/ || $2 ~ /\*$/ || $1 ~ /^\s*[0-9]+$/ || $2 ~ /^\s*[0-9]+$/) && \
    /FAT32/ && !/Extended/ {
        val_to_check = ""
        if ($2 == "*") { # Boot flag present, start sector is $3
            val_to_check = $3
        } else if ($1 ~ image_basename && $2 ~ /^[0-9]+$/) { # Device name in $1, start sector in $2
             val_to_check = $2
        } else if ($1 ~ /^[0-9]+$/ && $0 ~ image_basename) { # Device name in $1 (no suffix), start sector in $1
             val_to_check = $1 # This case is less likely for start sector, usually $2 or $3
        } else { # Try $2 as start sector by default if no boot flag
             val_to_check = $2
        }

        if (val_to_check ~ /^[0-9]+$/ && val_to_check > 0) {
            print val_to_check;
            exit;
        }
    }
')

if [[ -z "$start_sector_val" ]] || ! [[ "$start_sector_val" =~ ^[0-9]+$ ]]; then
    error "Could not determine start sector of FAT32 boot partition for '$image_filename' from fdisk output:\n$fdisk_output"
fi
readonly start_sector="$start_sector_val"
log "Determined boot partition start sector: $start_sector"

readonly boot_partition_offset=$((start_sector * sector_size))
log "Calculated boot partition offset: $boot_partition_offset bytes"

# Create a temporary mtoolsrc file
readonly mtoolsrc_file=$(mktemp)
echo "drive x: file=\"$image_filename\" offset=${boot_partition_offset}" > "$mtoolsrc_file"
export MTOOLSRC="$mtoolsrc_file"

# Ensure mtoolsrc cleanup happens even on script exit/error
trap 'log "Cleaning up temporary mtoolsrc..."; rm -f "$mtoolsrc_file" 2>/dev/null; unset MTOOLSRC; log "mtools cleanup complete."' EXIT INT TERM
# ---

# --- Modify image using mtools ---
log "Copying required .dtb files and kernel using mtools..."
# -o: overwrite if exists, -v: verbose
if ! mcopy -o -v "x:/bcm2710-rpi-3-b-plus.dtb" .; then
    log "Warning: bcm2710-rpi-3-b-plus.dtb not found in boot partition or mcopy failed."
    exit 1
fi
if ! mcopy -o -v "x:/bcm2711-rpi-4-b.dtb" .; then
    log "Warning: bcm2711-rpi-4-b.dtb not found in boot partition or mcopy failed."
    exit 1
fi
# copy pi5 even though unavaliable as a qemu fork is imcoming
if ! mcopy -o -v "x:/bcm2712-rpi-5-b.dtb" .; then
    log "Warning: bcm2712-rpi-5-b.dtb not found in boot partition or mcopy failed."
    exit 1
fi
if ! mcopy -o -v "x:/kernel8.img" .; then
    error "Failed to copy kernel8.img from boot partition using mtools."
fi
log ".dtb files (if present) and kernel copied using mtools."

log "Configuring user and enabling SSH using mtools..."
# Create ssh and userconf files locally first
temp_ssh_file=$(mktemp)
touch "$temp_ssh_file"

temp_userconf_file=$(mktemp)
echo "$user_conf_line" > "$temp_userconf_file"

# Copy them to the boot partition using mtools
if ! mcopy -o -v "$temp_ssh_file" "x:/ssh"; then
    rm -f "$temp_ssh_file" "$temp_userconf_file" # Clean up local temp files
    error "Failed to copy ssh file to boot partition using mtools."
fi
log "SSH file copied to boot partition."

if ! mcopy -o -v "$temp_userconf_file" "x:/userconf"; then
    rm -f "$temp_ssh_file" "$temp_userconf_file" # Clean up local temp files
    error "Failed to copy userconf file to boot partition using mtools."
fi
log "Userconf file copied to boot partition."

rm -f "$temp_ssh_file" "$temp_userconf_file" # Clean up local temp files
log "User configured and SSH enabled on boot partition using mtools."
# ---

# --- Image Resizing and Final Steps ---
log "Calculating size for '$image_filename'..."
current_size=$(stat -c%s "$image_filename")
if ((current_size == 0)); then
    error "Image file '$image_filename' has zero size."
fi

n=$((current_size - 1))
n=$((n | n >> 1))
n=$((n | n >> 2))
n=$((n | n >> 4))
n=$((n | n >> 8))
n=$((n | n >> 16))
n=$((n | n >> 32))
next_power_of_2=$((n + 1))

log "Current size: $current_size"
log "Next power of 2 size: $next_power_of_2"

log "Resizing image '$image_filename' to $next_power_of_2 bytes..."
if ! qemu-img resize "$image_filename" "$next_power_of_2"; then
    error "Failed to resize image '$image_filename'."
fi
log "Image resized successfully."

# Write results to local files
output_filename_info="filename.info"
echo "$image_filename" > "$output_filename_info"
log "Results written to '$output_filename_info'."

log "Script finished successfully."
exit 0
