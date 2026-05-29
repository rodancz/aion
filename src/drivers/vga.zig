const VGA_BUFFER: [*]volatile u16 = @ptrFromInt(0xB8000);
const VGA_WIDTH: usize = 80;
const VGA_HEIGHT: usize = 25;

var cursor_x: usize = 0;
var cursor_y: usize = 0;
var color: u8 = 0x0F;

fn entry_at(x: usize, y: usize) usize {
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
    var y: usize = 0;
    while (y < VGA_HEIGHT - 1) : (y += 1) {
        var x: usize = 0;
        while (x < VGA_WIDTH) : (x += 1) {
            VGA_BUFFER[entry_at(x, y)] = VGA_BUFFER[entry_at(x, y + 1)];
        }
    }
    const blank = @as(u16, 0x20) | (@as(u16, color) << 8);
    var x: usize = 0;
    while (x < VGA_WIDTH) : (x += 1) {
        VGA_BUFFER[entry_at(x, VGA_HEIGHT - 1)] = blank;
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
    for (s) |c| {
        put_char(c);
    }
}
