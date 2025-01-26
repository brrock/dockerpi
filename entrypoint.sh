#!/bin/sh

# GPIO Configuration Function
setup_gpio() {
  if [ "$PI_GPIO_ENABLED" = "1" ] && [ -e "$PI_GPIO_CHIP" ]; then
    echo "Configuring GPIO Passthrough for ${PI_MODEL}"
    
    # Export GPIO chip to container
    chmod 666 "$PI_GPIO_CHIP"
    
    # Additional GPIO configuration can be added here
    # For example: setting up specific GPIO pins, permissions, etc.
  else
    echo "GPIO support disabled or device not found"
  fi
}

# RAM Configuration Mapping
ram_config() {
  local model="$1"
  local ram_size="$2"
  
  case "${model}-${ram_size}" in
    "pi4-1g")    echo "1024m" ;;
    "pi4-2g")    echo "2048m" ;;
    "pi4-4g")    echo "4096m" ;;
    "pi4-8g")    echo "8192m" ;;
    "pi5-4g")    echo "4096m" ;;
    "pi5-8g")    echo "8192m" ;;
    "pi5-16g")   echo "16384m" ;;
    *)           echo "4096m" ;; # Default
  esac
}

# Model Configuration Function
model_config() {
  local target="$1"
  local ram_size="$2"

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
