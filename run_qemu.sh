#!/bin/bash
set -e
cd "$(dirname "$0")"

if [ ! -f aion.iso ]; then
    echo "Building ISO first..."
    ./run.sh
fi

cp /usr/share/edk2/OvmfX64/OVMF_VARS.fd /tmp/OVMF_VARS.fd 2>/dev/null
exec qemu-system-x86_64 \
    -drive if=pflash,format=raw,readonly=on,file=/usr/share/edk2/OvmfX64/OVMF_CODE.fd \
    -drive if=pflash,format=raw,file=/tmp/OVMF_VARS.fd \
    -cdrom aion.iso \
    -m 256M \
    -nographic \
    -nic user,model=e1000e,dns=1.1.1.1 \
    -no-reboot \
    -no-shutdown
