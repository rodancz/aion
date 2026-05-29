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
