#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "=== Building CPUMAIN AI OS ==="
zig build

echo "=== Preparing kernel ==="
objcopy -S zig-out/bin/cpumain iso/boot/cpumain

echo "=== Creating bootable ISO ==="
grub-mkrescue -o cpumain.iso iso/ 2>/dev/null

echo ""
echo "=== DONE ==="
echo "ISO ready: cpumain.iso"
echo ""
echo "To write to USB:"
echo "  sudo dd if=cpumain.iso of=/dev/sdX bs=4M status=progress"
echo ""
echo "To test in QEMU:"
echo "  ./run_qemu.sh"
