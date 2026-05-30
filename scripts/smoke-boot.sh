#!/bin/bash
# Smoke test: builds AionOS, boots in QEMU, verifies shell prompt appears
set -e
cd "$(dirname "$0")/.."

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

BOOT_TIMEOUT=30
BOOT_MARKER="System ready"

echo "=== Smoke Test: AionOS Boot ==="

# Step 1: Build
echo -n "[1/4] Building kernel... "
zig build 2>/dev/null && echo "OK" || { echo -e "${RED}FAIL${NC}"; exit 1; }

# Step 2: Prepare ISO
echo -n "[2/4] Creating boot ISO... "
objcopy -S zig-out/bin/aion iso/boot/aion 2>/dev/null
grub-mkrescue -o aion.iso iso/ 2>/dev/null && echo "OK" || { echo -e "${RED}FAIL${NC}"; exit 1; }

# Step 3: Boot in QEMU, capture serial output
echo -n "[3/4] Booting in QEMU... "
QEMU_LOG=$(mktemp)
cp /usr/share/edk2/OvmfX64/OVMF_VARS.fd /tmp/OVMF_VARS.fd 2>/dev/null || true

qemu-system-x86_64 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/OvmfX64/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \
    -cdrom aion.iso \
    -m 256M \
    -nographic \
    -nic user,model=e1000e,dns=1.1.1.1 \
    -no-reboot \
    -no-shutdown \
    &>"$QEMU_LOG" &
QEMU_PID=$!

# Step 4: Wait for boot marker
echo -n "[4/4] Waiting for '$BOOT_MARKER'... "
FOUND=0
for i in $(seq 1 $BOOT_TIMEOUT); do
    sleep 1
    if grep -q "$BOOT_MARKER" "$QEMU_LOG" 2>/dev/null; then
        FOUND=1
        break
    fi
    # Check if QEMU died early
    if ! kill -0 $QEMU_PID 2>/dev/null; then
        break
    fi
done

# Cleanup
kill $QEMU_PID 2>/dev/null || true
wait $QEMU_PID 2>/dev/null || true

if [ "$FOUND" -eq 1 ]; then
    echo -e "${GREEN}OK${NC}"
    echo ""
    echo "=== PASS: AionOS booted to shell ==="
    rm -f "$QEMU_LOG"
    exit 0
else
    echo -e "${RED}FAIL${NC}"
    echo ""
    echo "=== FAIL: Boot marker not found in ${BOOT_TIMEOUT}s ==="
    echo ""
    echo "Last 20 lines of QEMU output:"
    tail -20 "$QEMU_LOG"
    rm -f "$QEMU_LOG"
    exit 1
fi
