# AionOS — AI Self-Healing Microkernel

A self-healing operating system written in Zig. Layer 3 can crash — the microkernel's AI daemon analyzes the fault and hot-patches the running kernel in under 2 seconds. No reboot required.

**Alpha v0.1.0** — ~6000 lines of Zig.

## Architecture

```
CPU -> Microkernel (stable, never crashes)
        ├── VMM (4-level paging)
        ├── PMM (bitmap allocator)  
        ├── kmalloc (slab allocator)
        ├── Watchdog (heartbeat monitor)
        ├── AI Daemon (crash analysis + rebuild)
        ├── ATA PIO driver (disk read/write)
        ├── FAT32 driver (real filesystem)
        ├── Virtual filesystem (ramfs)
        ├── Network stack (e1000, DHCP, TCP, UDP, DNS, HTTP, TLS)
        ├── Crypto (SHA-256, AES-128, RSA-2048, TLS 1.2 client)
        └── Layer 3 (modifiable, can crash)
             ├── Shell (20+ commands)
             ├── Text editor
             ├── VFS (ramfs)
             └── IPC queue
```

## Features

| Category | What |
|----------|------|
| **Self-healing** | `crash` kills Layer 3, AI rebuilds in <2s |
| **Filesystem** | VFS (RAM) + FAT32 (real disk) read/write |
| **Editor** | Built-in text editor (`/s` save, `/dN` delete, `/iN` insert) |
| **Persistence** | `save` to FAT32 disk, `load` back, survives reboots |
| **Network** | e1000 NIC, DHCP, TCP stack, DNS resolver |
| **Crypto** | SHA-256, AES-128-CBC, RSA-2048, TLS 1.2 |
| **Shell** | `cd`, `ls`, `mkdir`, `cat`, `write`, `rm`, `edit`, `ip`, `ai`, +more |
| **Display** | VGA text mode + GOP framebuffer |
| **Keyboard** | PS/2 with IRQ + polling fallback |

## Commands

```
FILES:   ls  cd  mkdir  cat  write  rm  edit
DISK:    storage  save  load
SYS:     info  who  mem  uptime  ver  clear  logo  reboot
NET:     net  ip  ai
DEMO:    crash  rebuild
```

## Building

```bash
# Requires: Zig 0.15+, NASM, grub-mkrescue
zig build                    # Build kernel
./run.sh                     # Create aion.iso
./run_qemu.sh                # Test in QEMU
```

## Install

```bash
sudo dd if=aion.iso of=/dev/sdX bs=1M status=progress && sync
# Or use the installer:
sudo ./install.sh
```

Boot from USB in UEFI mode (disable Secure Boot).

## License

MIT — built by anon.
