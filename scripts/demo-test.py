#!/usr/bin/env python3
"""Automated AionOS self-healing demo test — progressive module hardening."""
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

print("=== AionOS Progressive Self-Healing Demo ===\n")

qemu = subprocess.Popen(
    ['qemu-system-x86_64',
     '-drive', 'if=pflash,format=raw,readonly=on,file=/usr/share/edk2/OvmfX64/OVMF_CODE.fd',
     '-drive', 'if=pflash,format=raw,file=/tmp/OVMF_VARS.fd',
     '-cdrom', 'aion.iso', '-m', '256M',
     '-serial', 'stdio', '-display', 'none',
     '-nic', 'user,model=e1000e,dns=1.1.1.1',
     '-no-reboot', '-no-shutdown'],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)

output = b""

def read_all():
    global output
    while True:
        r, _, _ = select.select([qemu.stdout], [], [], 0.05)
        if not r: break
        try:
            data = os.read(qemu.stdout.fileno(), 4096)
            if data: output += data
        except: break

def wait_for(marker, timeout=30):
    global output
    deadline = time.time() + timeout
    while time.time() < deadline:
        read_all()
        if marker.encode() in output: return True
        time.sleep(0.2)
    return False

def send(cmd):
    global output
    output = b""
    qemu.stdin.write((cmd + "\r\n").encode())
    qemu.stdin.flush()
    time.sleep(0.3)

def send_raw(cmd):
    qemu.stdin.write((cmd + "\r\n").encode())
    qemu.stdin.flush()

# Boot
print("Booting...", end=" ", flush=True)
if not wait_for("System ready", 45):
    print(f"{RED}FAIL (timeout){NC}")
    qemu.kill(); sys.exit(1)
print(f"{GREEN}OK{NC}")
time.sleep(1)

checks = 0
passed = 0

def test(name, *patterns, wait=3):
    global checks, passed, output
    checks += 1
    time.sleep(wait)
    read_all()
    for p in patterns:
        if p.encode() not in output:
            print(f"  {RED}FAIL{NC}: {name} (missing '{p}')")
            return
    passed += 1
    print(f"  {GREEN}OK{NC}: {name}")

# Test 1: crash (v1 -> v2)
print("--- v1: crash (shell) ---")
output = b""; send_raw("crash")
test("crash", "LAYER 3 CRASH", "restart_layer3", "Module upgraded", wait=5)

# Test 2: crash blocked by v2
print("--- v2: crash (shell blocked) ---")
send("crash")
test("crash-blocked", "blocks this crash type", wait=2)

# Test 3: crash-vfs (v2 -> v3)
print("--- v2: crash-vfs (vfs still open) ---")
output = b""; send_raw("crash-vfs")
test("crash-vfs", "LAYER 3 CRASH", "reset_vfs", "Purging VFS", "Module upgraded", wait=5)

# Test 4: crash-vfs blocked by v3
print("--- v3: crash-vfs (vfs blocked) ---")
send("crash-vfs")
test("crash-vfs-blocked", "blocks this crash type", wait=2)

# Test 5: crash-net (v3 -> v4)
print("--- v3: crash-net (net still open) ---")
output = b""; send_raw("crash-net")
test("crash-net", "LAYER 3 CRASH", "reset_network", "Resetting TCP", "Module upgraded", wait=5)

# Test 6: crash-net blocked by v4
print("--- v4: crash-net (net blocked) ---")
send("crash-net")
test("crash-net-blocked", "blocks this crash type", wait=2)

# Test 7: fault (CPU exception, always fires)
print("--- fault (real exception) ---")
output = b""; send_raw("fault")
test("fault", "FAULT", "Executing recovery", wait=5)

# Test 8: stat dashboard
print("--- stat dashboard ---")
send("stat")
test("stat", "AionOS Status", "v0.1.1-alpha", "layer3_v4", wait=1)

# Cleanup
qemu.kill(); qemu.wait()
print(f"\n{'='*40}")
print(f"Results: {passed}/{checks} checks passed")
if passed == checks:
    print(f"{GREEN}ALL PASS{NC}")
else:
    print(f"{RED}{checks - passed} FAILED{NC}")
    sys.exit(1)
