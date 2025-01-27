#!/bin/sh
# Raspberry Pi Emulation Script with Enhanced Pi 5 Support

# Constants
GIB_IN_BYTES="1073741824"
DEFAULT_TARGET="pi4"
IMAGE_PATH="/sdcard/filesystem.img"
ZIP_PATH="/filesystem.zip"

# Detect and prepare filesystem image
prepare_filesystem() {
  if [ ! -e "$IMAGE_PATH" ]; then
    echo "No filesystem detected at ${IMAGE_PATH}!"
    if [ -e "$ZIP_PATH" ]; then
      echo "Extracting fresh filesystem..."
      unzip "$ZIP_PATH"
      mv -- *.img "$IMAGE_PATH"
    else
      exit 1
    fi
  fi
  
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
  case "${target}" in
    "pi4")
      EMULATOR="qemu-system-aarch64"
      MACHINE="raspi4b"
      KERNEL="/root/kernels/pi4/kernel7l.img"
      DTB="/root/kernels/pi4/bcm2711-rpi-4-b.dtb"
      RAM=$(ram_config "pi4" "${ram_size}")
      ROOT="/dev/mmcblk0p2"
      ;;
    
    "pi5")
      EMULATOR="qemu-system-aarch64"
      MACHINE="raspi5b"
      KERNEL="/root/kernels/pi5/kernel_2712.img"
      DTB="/root/kernels/pi5/bcm2712-rpi-5-b.dtb"
      RAM=$(ram_config "pi5" "${ram_size}")
      ROOT="/dev/mmcblk0p2"
      ;;
    
    *)
      echo "Unsupported model: ${target}"
      exit 1
      ;;
  esac
}

# Main Execution
main() {
  local target="${1:-pi4}"
  local ram_size="${2:-4g}"
  local image_path="/sdcard/filesystem.img"

  # Setup GPIO
  setup_gpio

  # Configure model and RAM
  model_config "${target}" "${ram_size}"

  # QEMU Launch Command with GPIO Support
  exec ${EMULATOR} \
    -machine "${MACHINE}" \
    -cpu cortex-a72 \
    -m "${RAM}" \
    -kernel "${KERNEL}" \
    -dtb "${DTB}" \
    -drive "file=${image_path},if=sd,format=raw" \
    -net nic -net user,hostfwd=tcp::5022-:22 \
    -display none \
    -serial mon:stdio \
    -device virtio-gpio-pci \
    -append "root=${ROOT} rootwait console=ttyAMA0,115200 quiet"
}

# Execute main function with arguments
main "$@"
