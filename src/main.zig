extern fn asm_sti() void;
extern fn asm_hlt() void;

const console = @import("drivers/console.zig");
const gdt = @import("arch/x86_64/gdt.zig");
const idt = @import("arch/x86_64/idt.zig");
const pic = @import("arch/x86_64/pic.zig");
const pit = @import("drivers/pit.zig");
const pmm = @import("core/pmm.zig");
const kmalloc = @import("core/kmalloc.zig");
const wd = @import("core/watchdog.zig");
const kbd = @import("drivers/keyboard.zig");
const shell = @import("shell.zig");
const isr = @import("arch/x86_64/isr.zig");
const mbi2 = @import("multiboot2.zig");
const vmm = @import("core/vmm.zig");
const l2 = @import("layer2.zig");
const ipc = @import("ipc/queue.zig");
const aidaemon = @import("ai/daemon.zig");
const pci = @import("bus/pci.zig");
const e1000 = @import("drivers/e1000.zig");
const arp = @import("net/arp.zig");
const udp = @import("net/udp.zig");
const tcp = @import("net/tcp.zig");
const dhcp = @import("net/dhcp.zig");
const vfs = @import("fs/vfs.zig");
const ata = @import("drivers/ata.zig");
const fat32 = @import("fs/fat32.zig");
const beep = @import("drivers/beep.zig");
const _unused_isr = isr;

var net_ready: bool = false;

export fn exception_handler(int_num: u64, err_code: u64) void {
    isr.exception_handler(int_num, err_code);
}

export fn irq_handler(int_num: u64) void {
    isr.irq_handler(int_num);
}

extern var __kernel_start: u8;
extern var __kernel_end: u8;

fn write_prompt() void {
    console.write_str(shell.get_prompt());
}

export fn kernel_main(magic: u32, mbi_addr: u32) noreturn {
    // Earliest possible display: write directly to VGA buffer
    const VGA_BUFFER: [*]volatile u16 = @ptrFromInt(0xB8000);
    VGA_BUFFER[0] = @as(u16, 'A') | (0x0F << 8);
    VGA_BUFFER[1] = @as(u16, 'I') | (0x0F << 8);
    VGA_BUFFER[2] = @as(u16, 'O') | (0x0F << 8);
    VGA_BUFFER[3] = @as(u16, 'N') | (0x0F << 8);

    console.init();
    console.init_vga();

    if (mbi2.parse(mbi_addr)) |iter| {
        var it = iter;
        var fb_found: bool = false;
        while (it.next()) |tag| {
            if (tag.tag_type == 8) {
                const fbtag: *const extern struct {
                    tag_type: u32, size: u32,
                    fb_addr: u64, fb_pitch: u32, fb_width: u32, fb_height: u32, fb_bpp: u8,
                } = @ptrCast(@alignCast(tag));
                if (fbtag.fb_addr != 0) {
                    console.init_fb(fbtag.fb_addr, fbtag.fb_pitch, fbtag.fb_width, fbtag.fb_height, fbtag.fb_bpp);
                    fb_found = true;
                }
            }
        }
        if (!fb_found) {
            console.init_vga();
        }
    }

    console.write_str("");
    console.write_str("=== AionOS v0.1.0-alpha ===");
    console.write_str("");
    _ = magic;

    const kernel_start: usize = @intFromPtr(&__kernel_start);
    const kernel_end: usize = @intFromPtr(&__kernel_end);

    console.write_str("[BOOT] GDT..."); gdt.init(); console.write_str("OK");
    console.write_str("[BOOT] IDT..."); idt.init(); console.write_str("OK");
    console.write_str("[BOOT] PIC..."); pic.init(); console.write_str("OK");
    console.write_str("[BOOT] PIT..."); pit.init(100); console.write_str("OK");
    console.write_str("[BOOT] PMM..."); pmm.init(mbi_addr, kernel_start, kernel_end); console.write_str("OK");
    console.write_str("[BOOT] Heap..."); {
        const p = kmalloc.kmalloc(32);
        if (p != null) { kmalloc.kfree(p.?); console.write_str("OK"); }
        else { console.write_str("FAIL"); }
    }

    console.write_str("[VMM] Creating Layer 3 space...");
    const l2_space = vmm.create_space();
    if (l2_space == null) {
        console.write_str("[VMM] FAILED");
    } else {
        const l2_phys = pmm.alloc_frame();
        if (l2_phys != null) {
            _ = vmm.map_page(l2_space.?, 0x400000, l2_phys.?, vmm.PAGE_PRESENT | vmm.PAGE_RW | vmm.PAGE_USER);
            console.write_str("[VMM] Mapped Layer 3 at 0x400000");

            const orig_cr3 = vmm.get_current_space();
            vmm.switch_to(l2_space.?);

            const l2_mem: [*]volatile u64 = @ptrFromInt(@as(usize, 0x400000));
            l2_mem[0] = 0xDEADBEEFCAFEBABE;
            if (l2_mem[0] == 0xDEADBEEFCAFEBABE) {
                console.write_str("[VMM] Layer 3 memory write/read OK");
            }

            vmm.switch_to(vmm.AddressSpace{ .pml4_phys = orig_cr3 });
            console.write_str("[VMM] Switched back to kernel space OK");
        }
        wd.set_zone(0x400000, 0x500000);
    }

    // Network init
    tcp.init();
    console.write_str("[NET] Scanning PCI for NIC...");
    if (pci.scan()) |nic| {
        pci.enable_device(nic);
        console.write_str("[NET] NIC found (vendor=");
        _ = nic.vendor_id;
        _ = nic.device_id;
        if (e1000.init(nic.bar0, nic.bar1)) {
            net_ready = true;
            console.write_str("[NET] e1000 ready");
            arp.gateway_mac[0] = 0x52;
            arp.gateway_mac[1] = 0x54;
            arp.gateway_mac[2] = 0x00;
            arp.gateway_mac[3] = 0x12;
            arp.gateway_mac[4] = 0x34;
            arp.gateway_mac[5] = 0x56;
            dhcp.start();
        } else {
            console.write_str("[NET] e1000 init failed");
        }
    } else {
        console.write_str("[NET] No NIC found");
    }

    // IPC + AI daemon
    const ai_queue = ipc.queue_create();
    if (ai_queue) |q| {
        wd.set_ai_queue(q);
        aidaemon.init(q);
        console.write_str("[AI] IPC queue + daemon ready");
    } else {
        console.write_str("[AI] Failed to create IPC queue");
    }

    // Layer 3
    console.write_str("[L3] Starting...");
    l2.init();

    // Virtual filesystem
    vfs.init();

    // ATA disk driver
    _ = ata.init();
    _ = fat32.init();

    console.write_str("[BOOT] Unmask IRQ0/1/11...");
    pic.unmask(0);
    pic.unmask(1);
    pic.unmask(11); // e1000 typically IRQ 11
    console.write_str("[BOOT] STI...");
    asm_sti();
    beep.boot_chime();
    console.clear();
    shell.show_logo();
    console.write_str("System ready. Type 'help'.");
    console.write_str("");

    // Arm watchdog now that Layer 3 is running
    wd.arm();

    var prompt_needed = true;
    while (true) {
        if (prompt_needed) {
            write_prompt();
            prompt_needed = false;
        }
        asm_hlt();

        process_network();
        kbd.poll();

        dhcp.tick();
        tcp.tick();

        // Layer 3
        l2.tick();

        // AI daemon + rebuild
        if (ai_queue) |q| {
            aidaemon.tick();
            if (ipc.queue_recv(q)) |msg| {
                if (msg.msg_type == ipc.MsgType.rebuild_cmd) {
                    console.write_str("[WATCHDOG] AI rebuild complete. Restarting Layer 3...");
                    wd.reset();
                    l2.restart();
                    prompt_needed = true;
                }
            }
        }

        // Keyboard input
        if (kbd.read_line()) |line| {
            if (line.len > 0) {
                _ = shell.process(line);
            }
            prompt_needed = true;
        }
    }
}

fn process_network() void {
    if (!net_ready) return;
    var rx_buf: [2048]u8 = undefined;
    while (e1000.receive_packet(rx_buf[0..])) |len| {
        if (len == 0) continue;
        arp.handle_packet(rx_buf[0..len]);
        udp.handle_packet(rx_buf[0..len]);
        tcp.handle_packet(rx_buf[0..len]);
        dhcp.handle_packet(rx_buf[0..len]);
    }
}
