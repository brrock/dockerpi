#!/bin/sh
# Raspberry Pi Emulation Script with Enhanced Pi 5 Support

# Constants
GIB_IN_BYTES="1073741824"
DEFAULT_TARGET="pi4"
IMAGE_PATH="/sdcard/filesystem.img"

# Detect and prepare filesystem image
prepare_filesystem() {

  
  # Resize image if needed
  image_size_in_bytes=$(qemu-img info --output json "$IMAGE_PATH" | grep "virtual-size" | awk '{print $2}' | sed 's/,//')
  if [[ "$(($image_size_in_bytes % ($GIB_IN_BYTES * 2)))" != "0" ]]; then
    new_size_in_gib=$((($image_size_in_bytes / ($GIB_IN_BYTES * 2) + 1) * 2))
    echo "Rounding image size up to ${new_size_in_gib}GiB..."
    qemu-img resize "$IMAGE_PATH" "${new_size_in_gib}G"
  fi
}

# Configure model-specific parameters
configure_model() {
  local target="$1"
  
  case "$target" in
    "pi4")
      EMULATOR="qemu-system-aarch64"
      MACHINE="raspi4b"
      KERNEL="/root/kernels/pi4/kernel7l.img"
      DTB="/root/kernels/pi4/bcm2711-rpi-4-b.dtb"
      MEMORY="4096m"
      ROOT="/dev/mmcblk0p2"
      CPU="cortex-a72"
      ;;
    
    "pi5")
      # Note: Limited QEMU support for Pi 5
      EMULATOR="qemu-system-aarch64"
      MACHINE="virt"  # Fallback to generic virt machine
      KERNEL="/root/kernels/pi5/kernel_2712.img"
      DTB="/root/kernels/pi5/bcm2712-rpi-5-b.dtb"
      MEMORY="8192m"
      ROOT="/dev/mmcblk0p2"
      CPU="cortex-a76"
      # Additional workarounds for Pi 5 emulation
      EXTRA_ARGS="-cpu max -smp 4"
      ;;
    
    *)
      echo "Unsupported Raspberry Pi model: ${target}"
      exit 1
      ;;
  esac
}

# Main execution
main() {
  local target="${1:-$DEFAULT_TARGET}"
  
  # Prepare filesystem
  prepare_filesystem
  
  # Configure model-specific parameters
  configure_model "$target"
  
  # QEMU Launch Command
  exec "$EMULATOR" \
    -machine "$MACHINE" \
    -cpu "$CPU" \
    -m "$MEMORY" \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=${IMAGE_PATH},if=sd,format=raw" \
    -net nic -net user,hostfwd=tcp::5022-:22 \
    -display none \
    -serial mon:stdio \
    $EXTRA_ARGS \
    -append "root=${ROOT} rootwait console=ttyAMA0,115200 quiet"
}

# Execute main function with arguments
main "$@"