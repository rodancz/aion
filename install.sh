#!/bin/bash
# CPUMAIN Installer — installs to a disk for native boot
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}CPUMAIN AI OS Installer v0.6.0${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Run as root: sudo ./install.sh${NC}"
    exit 1
fi

ISO="$(dirname "$0")/cpumain.iso"
if [ ! -f "$ISO" ]; then
    echo -e "${RED}cpumain.iso not found. Run ./run.sh first.${NC}"
    exit 1
fi

echo "Available disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS | grep -E "disk|NAME" | head -20
echo ""

read -p "Enter target disk (e.g. sda, nvme0n1): " DISK
TARGET="/dev/$DISK"

if [ ! -b "$TARGET" ]; then
    echo -e "${RED}$TARGET is not a valid block device${NC}"
    exit 1
fi

echo ""
echo -e "${RED}WARNING: This will ERASE all data on $TARGET${NC}"
read -p "Type YES to confirm: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then
    echo "Aborted."
    exit 0
fi

echo "Writing CPUMAIN to $TARGET..."
dd if="$ISO" of="$TARGET" bs=1M status=progress conv=fsync
sync

echo ""
echo -e "${GREEN}CPUMAIN installed to $TARGET${NC}"
echo "Boot from this disk in UEFI mode (disable Secure Boot)."
