const port = @import("../arch/x86_64/port.zig");

pub fn beep(freq: u16, duration_ms: u16) void {
    if (freq == 0) return;
    const div: u16 = @truncate(1193180 / freq);
    port.outb(0x43, 0xB6);
    port.outb(0x42, @truncate(div));
    port.outb(0x42, @truncate(div >> 8));
    const tmp = port.inb(0x61);
    port.outb(0x61, tmp | 3);
    var i: u32 = 0;
    while (i < @as(u32, duration_ms) * 500) : (i += 1) {}
    port.outb(0x61, tmp & 0xFC);
}

pub fn boot_chime() void {
    beep(800, 60);
    beep(1000, 60);
    beep(1200, 100);
}
