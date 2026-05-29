# Aion — AI Self-Healing Microkernel

A self-healing operating system written in Zig. When the kernel crashes, an AI daemon analyzes the fault, generates a fix, and hot-patches the running kernel — all in under 2 seconds. No reboot required.

## Architecture

```
┌─────────────────────────────────────────┐
│  CPU                                    │
│  └── Microkernel (stable, never crashes)│
│       ├── VMM    (4-level paging)       │
│       ├── PMM    (bitmap allocator)     │
│       ├── kmalloc (slab allocator)       │
│       ├── Watchdog (heartbeat monitor)  │
│       ├── AI Daemon (crash analysis)    │
│       ├── Network Stack                 │
│       │   ├── e1000 NIC driver          │
│       │   ├── ARP, UDP, TCP             │
│       │   ├── DHCP client               │
│       │   ├── DNS resolver              │
│       │   ├── HTTP/S client             │
│       │   └── TLS 1.2 (RSA+AES-CBC)    │
│       ├── Crypto                        │
│       │   ├── SHA-256 + HMAC + PRF      │
│       │   ├── AES-128-CBC               │
│       │   └── RSA-2048 (bigint)         │
│       └── Drivers                       │
│           ├── PS/2 Keyboard (polling)   │
│           ├── VGA text mode              │
│           └── GOP Framebuffer           │
│                                          │
│  └── Layer 3 (modifiable, can crash)    │
│       ├── Shell                         │
│       ├── IPC                           │
│       └── User Applications             │
└─────────────────────────────────────────┘
```

## Self-Healing Flow

1. **Layer 3 crashes** — null pointer dereference, page fault, etc.
2. **Watchdog detects** heartbeat loss within 200 ticks (~2 seconds)
3. **AI Daemon receives** crash report via IPC queue
4. **API call dispatched** to configured AI endpoint (OpenAI/Anthropic/OpenCode/Claude)
5. **Patch generated** from AI response
6. **Layer 3 rebuilt** and restarted — system resumes normal operation

Without an API key, the daemon falls back to heuristic analysis.

## Building

```bash
# Requires: Zig 0.15+, NASM, grub-mkrescue
zig build                    # Build kernel
./run.sh                     # Create bootable ISO
./run_qemu.sh                # Test in QEMU (UEFI)
```

## Testing on Hardware

```bash
sudo dd if=aion.iso of=/dev/sdX bs=1M status=progress && sync
```

Boot from USB in **UEFI mode** (disable Secure Boot). Tested on Dell Latitude 5290.

## Install

```bash
sudo ./install.sh            # Interactive installer
```

## Commands

| Command | Description |
|---------|-------------|
| `help` | List all commands |
| `info` | System status + uptime |
| `who` | Architecture overview |
| `crash` | Trigger Layer 3 crash (self-healing demo) |
| `rebuild` | Simulate AI rebuild |
| `mem` | Memory statistics |
| `clear` | Clear screen |
| `net` | Network status |
| `ip ADDR GW DNS` | Configure static IP |
| `ai` | AI daemon status |
| `ai:endpoint URL` | Set AI API endpoint |
| `ai:key KEY` | Set API key |
| `ai:model MODEL` | Set AI model name |
| `uptime` | System uptime |
| `echo` | Print text |
| `ls` | List directory |
| `cd DIR` | Change directory |
| `logo` | ASCII boot logo |

## Verified

- Boots on QEMU (UEFI + BIOS via GRUB)
- DHCP client works (tested with QEMU SLIRP)
- TCP handshake verified (SYN→SYN-ACK→ACK)
- Layer 3 crash → AI rebuild cycle
- PS/2 keyboard with IRQ + polling fallback
- VGA text mode + GOP framebuffer

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Language | Zig (freestanding, no stdlib) |
| Boot | NASM → Multiboot2 → GRUB → UEFI |
| Arch | x86_64 |
| Lines | ~5500 |

## License

MIT — built by anon.
