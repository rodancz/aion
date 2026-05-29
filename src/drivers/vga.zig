const VGA_BUFFER: [*]volatile u16 = @ptrFromInt(0xB8000);
const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;

var cursor_x: usize = 0;
var cursor_y: usize = 0;
var color: u8 = 0x0F;

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

pub fn put_char(c: u8) void {
    if (c == '\n') {
        cursor_x = 0;
        cursor_y += 1;
    } else if (c == '\r') {
        cursor_x = 0;
    } else {
        VGA_BUFFER[cursor_y * VGA_WIDTH + cursor_x] = @as(u16, c) | (@as(u16, color) << 8);
        cursor_x += 1;
    }

    if (cursor_x >= VGA_WIDTH) {
        cursor_x = 0;
        cursor_y += 1;
    }
    if (cursor_y >= VGA_HEIGHT) {
        // Fast scroll: copy line 1->0, 2->1, etc using row-level copy
        var y: usize = 0;
        const line_size = VGA_WIDTH;
        while (y < VGA_HEIGHT - 1) : (y += 1) {
            const src = y + 1;
            var x: usize = 0;
            while (x < line_size) : (x += 1) {
                VGA_BUFFER[y * line_size + x] = VGA_BUFFER[src * line_size + x];
            }
        }
        // Clear last line
        const blank = @as(u16, 0x20) | (@as(u16, color) << 8);
        var x: usize = 0;
        while (x < line_size) : (x += 1) {
            VGA_BUFFER[(VGA_HEIGHT - 1) * line_size + x] = blank;
        }
        cursor_y = VGA_HEIGHT - 1;
    }
}

pub fn write_str(s: []const u8) void {
    for (s) |c| put_char(c);
}
