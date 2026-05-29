#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Building Aion ==="
zig build

echo "=== Preparing kernel ==="
objcopy -S zig-out/bin/aion iso/boot/aion

echo "=== Creating bootable ISO ==="
grub-mkrescue -o aion.iso iso/ 2>/dev/null

echo ""
echo "=== DONE ==="
echo "ISO ready: aion.iso"
echo ""
echo "To write to USB:"
echo "  sudo dd if=aion.iso of=/dev/sdX bs=4M status=progress"
echo ""
echo "To test in QEMU:"
echo "  ./run_qemu.sh"
