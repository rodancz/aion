# AionOS — Self-Healing Microkernel

A small operating system written in Zig that can survive crashes.
Layer 3 crashes — the watchdog notices, the AI daemon picks a fix,
and the kernel swaps in a working module. No reboot needed.

**v0.1.0-alpha** — ~6500 lines of Zig. Boots in QEMU.

## What it does

1. **Boots to a shell** — 24 commands, text editor, filesystem, networking
2. **Survives crashes** — watchdog detects dead Layer 3 in <2 seconds
3. **Classifies the fault** — AI daemon picks a recovery action (local keywords or API)
4. **Swaps the module** — switches from crashable v1 to crash-resistant v2 at runtime
5. **Stays up** — same crash command that killed it before now gets ignored

## Proof it works

```bash
./scripts/smoke-boot.sh   # Builds, boots in QEMU, confirms shell appears
```

In the QEMU shell, try this:

```
aion> crash          # Kills Layer 3
[AI] Crash report received...
[AI] Local: restart_layer3
[AI] Executing recovery: restart_layer3
[L3] Module upgraded to: layer3_v2
[L3] Layer 3 restarted (module: layer3_v2)
aion> crash          # Try again
[L3] Module layer3_v2 is crash-resistant — crash ignored
aion> info           # Check: module v2, 1 crash, 1 upgrade
```

## Architecture

```
Microkernel (stable)
├── Watchdog — heartbeat monitor, flags crashes
├── AI Daemon — classifies fault → picks safe action
├── Module table — v1 (crashable) → v2 (crash-resistant)
├── VMM / PMM / kmalloc — memory
├── VFS (ramfs) + FAT32 (disk) — filesystem
├── e1000 + DHCP + TCP + DNS + HTTP — networking
├── SHA-256 + AES-128 + RSA-2048 + TLS 1.2 — crypto
└── PS/2 keyboard + VGA + framebuffer — display
```

## Commands

```
FILES:  ls  cd  mkdir  cat  write  rm  edit  echo
DISK:   save  load  storage
SYS:    info  who  mem  uptime  ver  clear  logo  reboot
L3:     modules  upgrade  crash  rebuild
NET:    net  ip  ai
PCI:    pci
```

## Recovery actions

The AI daemon classifies crashes into one of four actions:

| Action | When | Source |
|--------|------|--------|
| `restart_layer3` | Default fallback | Any crash → restart + upgrade module |
| `reset_vfs` | Filesystem crash keywords | `src/ai/daemon.zig:classify_local()` |
| `reset_network` | Network crash keywords | `src/ai/daemon.zig:classify_local()` |
| `no_action` | False alarm | No restart needed |

If an OpenAI-compatible API is configured, the daemon asks the model to pick one.
Otherwise it uses keyword matching locally. The API **chooses from the menu** —
it cannot generate arbitrary code.

## Build

```bash
# Requires: Zig 0.15+, NASM, grub-mkrescue
zig build
./run.sh          # creates aion.iso
./run_qemu.sh     # boots in QEMU
```

## Install to USB

```bash
sudo dd if=aion.iso of=/dev/sdX bs=1M status=progress && sync
# or: sudo ./install.sh
```

Boot in UEFI mode (disable Secure Boot).

## Roadmap (what's next)

- Real `reset_vfs` and `reset_network` recovery implementations
- Crash from actual page faults (not just the `crash` command)
- More modules in the table (v3, v4...)
- Serial console for headless recovery
- Multi-process isolation

## License

MIT
