const VGA_BUFFER: [*]volatile u16 = @ptrFromInt(0xB8000);
const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;

var cursor_x: usize = 0;
var cursor_y: usize = 0;
var color: u8 = 0x0F;

inline fn entry_at(x: usize, y: usize) usize {
    return y * VGA_WIDTH + x;
}

pub fn init() void {
    cursor_x = 0;
    cursor_y = 0;
    color = 0x0F;
    clear();
}

pub fn clear() void {
    const blank = @as(u16, 0x20) | (@as(u16, color) << 8);
    var i: usize = 0;
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 1) {
        VGA_BUFFER[i] = blank;
    }
    cursor_x = 0;
    cursor_y = 0;
}

fn scroll() void {
    // Fast scroll using 64-bit copies (8 chars at a time)
    const total_words = VGA_WIDTH * (VGA_HEIGHT - 1);
    var i: usize = 0;
    while (i < total_words) : (i += 4) {
        const src: *volatile u64 = @ptrFromInt(@intFromPtr(&VGA_BUFFER[VGA_WIDTH + i]));
        const dst: *volatile u64 = @ptrFromInt(@intFromPtr(&VGA_BUFFER[i]));
        dst.* = src.*;
    }
    // Clear last line
    const blank = @as(u16, 0x20) | (@as(u16, color) << 8);
    const blank64 = (@as(u64, blank) << 48) | (@as(u64, blank) << 32) | (@as(u64, blank) << 16) | blank;
    i = VGA_WIDTH * (VGA_HEIGHT - 1);
    while (i < VGA_WIDTH * VGA_HEIGHT) : (i += 4) {
        const dst: *volatile u64 = @ptrFromInt(@intFromPtr(&VGA_BUFFER[i]));
        dst.* = blank64;
    }
}

pub fn put_char(c: u8) void {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += 1;
    } else if (c == '\r') {
        cursor_x = 0;
    } else {
        VGA_BUFFER[entry_at(cursor_x, cursor_y)] = @as(u16, c) | (@as(u16, color) << 8);
        cursor_x += 1;
    }

    if (cursor_x >= VGA_WIDTH) {
        cursor_x = 0;
        cursor_y += 1;
    }
    if (cursor_y >= VGA_HEIGHT) {
        scroll();
        cursor_y = VGA_HEIGHT - 1;
    }
}

pub fn write_str(s: []const u8) void {
    for (s) |c| put_char(c);
}
