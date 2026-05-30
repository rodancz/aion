extern fn asm_outb(port: u16, value: u8) void;
extern fn asm_inb(port: u16) u8;

const COM1: u16 = 0x3F8;

var initialized = false;

pub fn init() void {
    asm_outb(COM1 + 1, 0x00);
    asm_outb(COM1 + 3, 0x80);
    asm_outb(COM1 + 0, 0x03);
    asm_outb(COM1 + 1, 0x00);
    asm_outb(COM1 + 3, 0x03);
    asm_outb(COM1 + 2, 0xC7);
    asm_outb(COM1 + 4, 0x0B);
    initialized = true;
}

fn tx_empty() bool {
    return (asm_inb(COM1 + 5) & 0x20) != 0;
}

pub fn write_byte(byte: u8) void {
    if (!initialized) return;
    while (!tx_empty()) {}
    asm_outb(COM1, byte);
}

pub fn write_str(s: []const u8) void {
    for (s) |c| {
        write_byte(c);
    }
    write_byte('\r');
    write_byte('\n');
}

fn data_ready() bool {
    return (asm_inb(COM1 + 5) & 0x01) != 0;
}

pub fn read_byte() ?u8 {
    if (!initialized or !data_ready()) return null;
    return asm_inb(COM1);
}

var line_buf: [256]u8 = [_]u8{0} ** 256;
var line_len: usize = 0;

pub fn read_line(buf: []u8) ?[]const u8 {
    if (!initialized) return null;
    while (line_len < buf.len - 1) {
        const byte = read_byte() orelse break;
        if (byte == '\r' or byte == '\n') {
            if (line_len == 0) continue;
            buf[line_len] = 0;
            const result = buf[0..line_len];
            line_len = 0;
            return result;
        }
        if (byte >= 0x20 and byte < 0x7F) {
            buf[line_len] = byte;
            line_len += 1;
        }
    }
    return null;
}
