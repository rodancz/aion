#!/usr/bin/env python3
"""Automated self-healing demo test — drives QEMU via pipes."""
import os, sys, time, subprocess, signal, select

GREEN = '\033[0;32m'
RED = '\033[0;31m'
NC = '\033[0m'

os.chdir(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Build
subprocess.run(['zig', 'build'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['objcopy', '-S', 'zig-out/bin/aion', 'iso/boot/aion'], stdout=subprocess.DEVNULL)
subprocess.run(['grub-mkrescue', '-o', 'aion.iso', 'iso/'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
subprocess.run(['cp', '/usr/share/edk2/OvmfX64/OVMF_VARS.fd', '/tmp/OVMF_VARS.fd'],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

print("=== Demo Test: AionOS Self-Healing ===")

qemu = subprocess.Popen(
    ['qemu-system-x86_64',
     '-drive', 'if=pflash,format=raw,readonly=on,file=/usr/share/edk2/OvmfX64/OVMF_CODE.fd',
     '-drive', 'if=pflash,format=raw,file=/tmp/OVMF_VARS.fd',
     '-cdrom', 'aion.iso',
     '-m', '256M',
     '-serial', 'stdio',
     '-display', 'none',
     '-nic', 'user,model=e1000e,dns=1.1.1.1',
     '-no-reboot', '-no-shutdown'],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)

output = b""

def read_all():
    global output
    while True:
        r, _, _ = select.select([qemu.stdout], [], [], 0.05)
        if not r:
            break
        try:
            data = os.read(qemu.stdout.fileno(), 4096)
            if data:
                output += data
        except:
            break

def wait_for(marker, timeout=30):
    global output
    deadline = time.time() + timeout
    while time.time() < deadline:
        read_all()
        if marker.encode() in output:
            return True
        time.sleep(0.2)
    return False

def send(cmd, clear=True):
    global output
    if clear:
        output = b""
    qemu.stdin.write((cmd + "\r\n").encode())
    qemu.stdin.flush()
    time.sleep(0.3)

# Boot
print("Booting...", end=" ", flush=True)
if wait_for("System ready", 45):
    print(f"{GREEN}OK{NC}")
else:
    print(f"{RED}FAIL (timeout){NC}")
    qemu.kill()
    sys.exit(1)

time.sleep(1)

# Test 1: crash-vfs (v1 is crashable, classify -> reset_vfs, v1->v2)
print("--- crash-vfs (v1, RESET_VFS) ---")
output = b""
qemu.stdin.write(b"crash-vfs\r\n")
qemu.stdin.flush()
time.sleep(6)
read_all()
print(f"  crash: {'OK' if b'LAYER 3 CRASH' in output else 'FAIL'}")
print(f"  classify: {'OK' if b'reset_vfs' in output else 'FAIL'}")
print(f"  purge: {'OK' if b'Purging VFS' in output else 'FAIL'}")
print(f"  upgrade: {'OK' if b'Module upgraded' in output else 'FAIL'}")

# Test 2: crash (v2 blocks all software crashes)
print("--- crash (v2 blocks) ---")
send("crash")
time.sleep(2)
read_all()
print(f"  blocked: {'OK' if b'crash-resistant' in output else 'FAIL'}")

# Test 3: crash-net (v2 also blocks)
print("--- crash-net (v2 blocks) ---")
send("crash-net")
time.sleep(2)
read_all()
print(f"  blocked: {'OK' if b'crash-resistant' in output else 'FAIL'}")

# Test 4: fault (real CPU exception — always fires, bypasses module check)
print("--- fault (real exception) ---")
output = b""
qemu.stdin.write(b"fault\r\n")
qemu.stdin.flush()
time.sleep(5)
read_all()
print(f"  exception: {'OK' if b'FAULT' in output else 'FAIL'}")
print(f"  recovery: {'OK' if b'Executing recovery' in output else 'FAIL'}")

# Test 5: info (show crash count)
print("--- info ---")
send("info")
time.sleep(1)
read_all()
print(f"  info: {'OK' if (b'Crashes' in output or b'crash' in output.lower()) else 'FAIL'}")

# Info
send("info")
time.sleep(1)
read_all()

print(f"\n=== Done ===")
qemu.kill()
qemu.wait()
