const serial = @import("serial.zig");
const fb = @import("framebuffer.zig");
const vga = @import("vga.zig");

var use_vga: bool = false;

pub fn init() void { serial.init(); }
pub fn init_fb(addr: u64, pitch: u32, w: u32, h: u32, bpp: u8) void { fb.init(addr, pitch, w, h, bpp); }
pub fn init_vga() void { vga.init(); use_vga = true; }

pub fn write_byte(c: u8) void {
    serial.write_byte(c);
    fb.put_char(c);
    if (use_vga) vga.put_char(c);
}
pub fn write_str(s: []const u8) void {
    for (s) |c| write_byte(c);
    write_byte('\r'); write_byte('\n');
}
pub fn write_inline(s: []const u8) void { for (s) |c| write_byte(c); }
pub fn clear() void {
    fb.clear();
    if (use_vga) vga.clear();
}
