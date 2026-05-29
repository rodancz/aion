# CPUMAIN — AI Self-Healing Microkernel

**Version 0.6.0** — a self-healing operating system written in Zig.

## Architecture

```
CPU → Microkernel (CPUMAIN) → Layer 3 → AI Daemon
         │
         ├── VMM (4-level paging)
         ├── PMM (bitmap allocator)
         ├── Watchdog (heartbeat monitor)
         ├── AI Daemon (crash analysis + rebuild)
         ├── Network stack (e1000, DHCP, TCP, UDP, DNS, HTTP, TLS)
         └── Drivers (keyboard, VGA, framebuffer, serial)
```

## How it works

When Layer 3 crashes, the microkernel's watchdog detects it. The AI daemon analyzes the crash, generates a fix, and hot-patches Layer 3 — all without rebooting. Rebuilds complete in under 2 seconds.

## Building

```bash
# Requires Zig 0.15+, NASM, grub-mkrescue
zig build                        # Build the kernel
./run.sh                         # Build ISO
./run_qemu.sh                    # Test in QEMU
```

## Testing on real hardware

```bash
sudo dd if=cpumain.iso of=/dev/sdX bs=1M status=progress && sync
```

Boot from USB in UEFI mode (disable Secure Boot).

## Commands

| Command | Description |
|---------|-------------|
| `help` | List all commands |
| `info` | System status |
| `who` | Architecture overview |
| `crash` | Trigger Layer 3 crash (self-healing demo) |
| `rebuild` | Simulated rebuild |
| `mem` | Memory statistics |
| `clear` | Clear screen |
| `net` | Network status |
| `ip` | Configure static IP |
| `uptime` | System uptime |
| `echo` | Print text |
| `ls` | List directory |
| `cd` | Change directory |
| `ai` | AI daemon status |
| `logo` | ASCII art logo |

## Tech Stack

- **Language:** Zig (freestanding, no stdlib)
- **Boot:** NASM → Multiboot2 → GRUB → UEFI
- **Networking:** Custom TCP/IP stack, e1000 NIC driver
- **Crypto:** SHA-256, AES-128-CBC, RSA, TLS 1.2 client
- **Memory:** PMM bitmap, slab allocator, 4-level paging

## License

MIT — built by anon.
