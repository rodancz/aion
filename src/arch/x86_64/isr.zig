const serial = @import("../../drivers/serial.zig");
const pic = @import("pic.zig");
const wd = @import("../../core/watchdog.zig");

var tick_count: u64 = 0;

pub fn exception_handler(int_num: u64, err_code: u64) void {
    _ = err_code;
    if (wd.is_recovering()) return;
    serial.write_str("=== FAULT ===");
    serial.write_str("Vector: ");
    write_num(int_num);
    wd.begin_recovery();
    wd.report_crash("exception");
}

pub fn irq_handler(int_num: u64) void {
    const irq: u32 = @truncate(int_num - 32);
    switch (irq) {
        0 => { tick_count += 1; wd.tick(); },
        1 => {},
        else => {},
    }
    pic.send_eoi(@truncate(irq));
}

fn write_num(n: u64) void {
    if (n == 0) { serial.write_byte('0'); return; }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) {
        buf[i] = @as(u8, @truncate(v % 10)) + '0';
        i += 1;
    }
    while (i > 0) { i -= 1; serial.write_byte(buf[i]); }
}

pub fn get_ticks() u64 {
    return tick_count;
}
