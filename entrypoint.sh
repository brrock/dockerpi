#!/usr/bin/env bash
set -euo pipefail

cd ~

# Read the image filename from setup
if [[ ! -f filename.info ]]; then
  echo "Error: filename.info not found. Run prep.sh first." >&2
  exit 1
fi
IMG=$(cat filename.info)

# Check for required files
for f in bcm2711-rpi-4-b.dtb bcm2710-rpi-3-b-plus.dtb kernel8.img; do
  if [[ ! -f $f ]]; then
    echo "Error: Required file $f not found in home directory. Run prep.sh first." >&2
    exit 1
  fi
done

# Default: Pi 4
MACHINE="raspi4b"
DTB="bcm2711-rpi-4-b.dtb"
KERNEL="kernel8.img"
QEMU_BIN="qemu-system-aarch64"
APPEND="console=ttyAMA0,115200 root=/dev/mmcblk0p2 rw"

# If first arg is 3b, switch to Pi 3 emulation
if [[ "${1:-}" == "3b" ]]; then
  MACHINE="raspi3b"
  DTB="bcm2710-rpi-3-b-plus.dtb"
  # kernel8.img is still used for 64-bit Pi 3 emulation
fi

# Run QEMU
exec $QEMU_BIN \
  -M $MACHINE \
  -m 1G \
  -dtb $DTB \
  -kernel $KERNEL \
  -drive file="$IMG",format=raw,if=sd,cache=writeback \
  -append "$APPEND" \
  -serial stdio \
  -device usb-net,netdev=net0 \
  -netdev user,id=net0,hostfwd=tcp::2222-:22 \
  -no-reboot -display none \
  -nographic
