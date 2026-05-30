# Changelog

## v0.1.1-alpha (2026-05-30)

### Progressive module hardening
- **4 modules** (v1→v4) with per-crash-type blocking instead of all-or-nothing
- v1: all crashable → v2: blocks shell → v3: blocks vfs → v4: blocks all software crashes
- Each crash type auto-upgrades to the module that blocks it
- `fault` (real CPU exception) always fires regardless of module version

### Self-healing
- AI daemon classifies crashes into 4 safe recovery actions
- `reset_vfs` actually purges VFS, `reset_network` resets TCP+DHCP
- Real exception recovery — `fault` triggers `ud2` → ISR → watchdog → recovery (no halt)
- `crash-vfs` / `crash-net` trigger specific crash types → AI picks matching action

### New commands
- `stat` — dashboard showing module, crashes, upgrades, network status
- `demo` — prints self-healing walkthrough
- `fault` — triggers real CPU exception (recoverable)
- Serial input — commands work via QEMU serial port

### Testing
- `./scripts/boot-check.sh` — one-command QEMU boot verification
- `./scripts/demo-test.py` — 8 automated self-healing checks (all pass)

### Cleanup
- CPUMAIN → AionOS branding
- Build artifacts removed from git
- Honest README — every claim points to source or demo

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
