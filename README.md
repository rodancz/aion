# AionOS — AI Self-Healing Microkernel

A self-healing operating system written in Zig. Layer 3 can crash — the microkernel detects the fault and resets Layer 3 in under 2 seconds. No reboot required.

**Alpha v0.1.0** — ~6000 lines of Zig.

## Architecture

```
CPU -> Microkernel (stable, never crashes)
        ├── VMM (4-level paging)
        ├── PMM (bitmap allocator)
        ├── kmalloc (slab allocator)
        ├── Watchdog (heartbeat monitor)
        ├── PCI bus scanner
        ├── ATA PIO driver (disk read/write)
        ├── FAT32 driver (real filesystem)
        ├── Virtual filesystem (ramfs)
        ├── Network stack (e1000, ARP, DHCP, TCP, UDP, DNS, HTTP)
        ├── Crypto (SHA-256, AES-128, RSA-2048, TLS 1.2 client)
        ├── AI Daemon (crash analysis demo)
        └── Layer 3 (modifiable, can crash)
             ├── Shell (20+ commands)
             ├── Text editor
             ├── VFS (ramfs)
             └── IPC queue
```

## Capabilities

### Implemented

| Category | What | Source |
|----------|------|--------|
| **Boot** | Multiboot2, GDT, IDT, PIC, PIT, page tables | `src/arch/`, `src/boot.asm`, `src/multiboot2.zig` |
| **Memory** | 4-level paging, bitmap PMM, slab kmalloc | `src/core/vmm.zig`, `src/core/pmm.zig`, `src/core/kmalloc.zig` |
| **Filesystem** | VFS (RAM) — create, read, write, delete, dirs | `src/fs/vfs.zig` |
| **Real disk** | ATA PIO read/write, FAT32 with persistent save/load | `src/drivers/ata.zig`, `src/fs/fat32.zig` |
| **Editor** | Built-in text editor (`/s` save, `/dN` delete, `/iN` insert) | `src/shell.zig` |
| **Persistence** | `save` to FAT32 disk, `load` back, survives reboots | `src/shell.zig`, `src/fs/fat32.zig` |
| **Network** | e1000 NIC, ARP, DHCP client, TCP/UDP sockets, DNS resolver, HTTP client | `src/drivers/e1000.zig`, `src/net/` |
| **Crypto** | SHA-256, AES-128-CBC, RSA-2048 keygen, TLS 1.2 client handshake | `src/crypto/`, `src/net/tls.zig` |
| **PCI** | Bus enumeration and device listing | `src/bus/pci.zig` |
| **Watchdog** | Heartbeat monitor — detects L3 dead after 200 ticks | `src/core/watchdog.zig` |
| **Crash/recovery** | `crash` kills L3, watchdog detects, AI prints status, L3 restarts | `src/layer2.zig`, `src/core/watchdog.zig` |
| **Shell** | `ls`, `cd`, `mkdir`, `cat`, `write`, `rm`, `edit`, `ip`, `net`, `ai`, `mem`, `uptime`, `ver`, `clear`, `who`, `info`, `reboot`, `crash`, `rebuild`, `logo`, `echo`, `help`, `save`, `load`, `pci` | `src/shell.zig` |
| **Display** | VGA text mode + GOP framebuffer | `src/drivers/vga.zig`, `src/drivers/framebuffer.zig` |
| **Keyboard** | PS/2 with IRQ + polling fallback | `src/drivers/keyboard.zig` |
| **Sound** | PC speaker beep (boot chime) | `src/drivers/beep.zig` |

### Experimental / Demo

| Category | What | Source |
|----------|------|--------|
| **AI self-healing** | Daemon receives crash report, builds JSON prompt, optionally calls OpenAI-compatible API, logs chatty "patching" messages, then resets Layer 3. No generated code is parsed, validated, or applied. | `src/ai/daemon.zig` |
| **TLS** | RSA+AES TLS 1.2 client — handshake works against test endpoints, limited cipher suite | `src/net/tls.zig`, `src/crypto/` |
| **Framebuffer** | GOP linear framebuffer with per-pixel pixel copy scrolling | `src/drivers/framebuffer.zig` |

### Planned

- AI-assisted crash classification (choose from a safe table of recovery actions)
- Module replacement for real hot-patching (not just state reset)
- QEMU smoke-test script (`./scripts/smoke-boot.sh`)
- Virtual memory page fault recovery
- Read-only file system with safe rollback
- Multi-process support

## Commands

```
FILES:   ls  cd  mkdir  cat  write  rm  edit  echo
DISK:    save  load
SYS:     info  who  mem  uptime  ver  clear  logo  reboot
NET:     net  ip  ai
PCI:     pci
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
