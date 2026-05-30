# Changelog

## v0.1.1-alpha (2026-05-30)

### Self-healing (real, not fake)
- AI daemon now **classifies** crashes into 4 safe recovery actions instead of pretending to generate patches
- **Module replacement** — Layer 3 v1 (crashable) auto-swaps to v2 (crash-resistant) on recovery
- **Real exception recovery** — `fault` triggers `ud2` → #UD exception → watchdog → recovery (no halt)
- Watchdog recovery now shows crash count and last crash reason (`info` command)
- `crash-vfs` / `crash-net` trigger specific crash reasons → AI picks matching action
- Recovery actions actually execute: `reset_vfs` purges VFS, `reset_network` resets TCP+DHCP

### Testing
- `./scripts/boot-check.sh` — one command builds + boots in QEMU + confirms shell appears

### Cleanup
- All CPUMAIN branding renamed to AionOS
- Build artifacts (`.zig-cache/`, `zig-out/`, ISOs) removed from git tracking
- README rewritten — every claim points to real source files or a demo you can run

---

## v0.1.0-alpha (2026-05-28)

### Core
- Multiboot2 bootloader, GDT, IDT, PIC, PIT
- 4-level paging VMM, bitmap PMM, slab kmalloc
- PS/2 keyboard (IRQ + polling), VGA text mode, GOP framebuffer

### Filesystem
- VFS (ramfs) — create, read, write, delete files and directories
- ATA PIO driver + FAT32 read/write — files survive reboots
- Built-in text editor with save/load to FAT32

### Networking
- Intel e1000 NIC driver
- ARP, DHCP client, TCP/UDP, DNS resolver, HTTP client
- SHA-256, AES-128-CBC, RSA-2048 keygen, TLS 1.2 client

### Shell (24 commands)
- Files: `ls`, `cd`, `mkdir`, `cat`, `write`, `rm`, `edit`, `echo`
- Disk: `save`, `load`, `storage`
- System: `info`, `who`, `mem`, `uptime`, `ver`, `clear`, `logo`, `reboot`
- Network: `net`, `ip`, `ai`
- Demo: `crash`, `rebuild`
- PCI: `pci`

### Watchdog + AI daemon
- Heartbeat monitor detects Layer 3 death in ~2s
- AI daemon scaffold (receives crash, can call OpenAI API, resets Layer 3)
- IPC queue for crash reports
