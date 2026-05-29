const port = @import("../arch/x86_64/port.zig");
const console = @import("console.zig");

const KBD_DATA: u16 = 0x60;
const KBD_STATUS: u16 = 0x64;

const BUF_SIZE: usize = 256;
var buf: [BUF_SIZE]u8 = [_]u8{0} ** BUF_SIZE;
var buf_head: usize = 0;
var buf_tail: usize = 0;
var line_ready: bool = false;
var line_buf: [BUF_SIZE]u8 = [_]u8{0} ** BUF_SIZE;
var line_len: usize = 0;
var last_poll: u64 = 0;

pub fn handle_irq() void { poll(); }

pub fn poll() void {
    const status = port.inb(KBD_STATUS);
    if ((status & 1) == 0) return;
    const sc = port.inb(KBD_DATA);
    if (sc & 0x80 != 0) return;
    const c = translate(sc);
    if (c == 0) return;

    if (c == '\n') {
        line_buf[line_len] = 0;
        line_ready = true;
        line_len = 0;
        console.write_byte('\r');
        console.write_byte('\n');
        return;
    }

    if (c == '\x08') {
        if (line_len > 0) {
            line_len -= 1;
            console.write_byte('\x08');
            console.write_byte(' ');
            console.write_byte('\x08');
        }
        return;
    }

    if (line_len < BUF_SIZE - 1) {
        line_buf[line_len] = c;
        line_len += 1;
        console.write_byte(c);
    }

    if (buf_head != buf_tail) {
        return;
    }
    buf[buf_head] = c;
    buf_head = (buf_head + 1) % BUF_SIZE;
}

pub fn read_line() ?[]const u8 {
    if (!line_ready) return null;
    line_ready = false;
    var len: usize = 0;
    while (len < BUF_SIZE and line_buf[len] != 0) : (len += 1) {}
    return line_buf[0..len];
}

pub fn read_line_editor() ?[]const u8 {
    return read_line();
}

pub fn get_char() ?u8 {
    if (buf_head == buf_tail) return null;
    const c = buf[buf_tail];
    buf_tail = (buf_tail + 1) % BUF_SIZE;
    return c;
}

fn translate(sc: u8) u8 {
    return switch (sc) {
        0x02 => '1',  0x03 => '2',  0x04 => '3',  0x05 => '4',
        0x06 => '5',  0x07 => '6',  0x08 => '7',  0x09 => '8',
        0x0A => '9',  0x0B => '0',  0x0C => '-',  0x0D => '=',
        0x0E => '\x08', 0x0F => '\t',
        0x10 => 'q',  0x11 => 'w',  0x12 => 'e',  0x13 => 'r',
        0x14 => 't',  0x15 => 'y',  0x16 => 'u',  0x17 => 'i',
        0x18 => 'o',  0x19 => 'p',  0x1A => '[',  0x1B => ']',
        0x1C => '\n',
        0x1E => 'a',  0x1F => 's',  0x20 => 'd',  0x21 => 'f',
        0x22 => 'g',  0x23 => 'h',  0x24 => 'j',  0x25 => 'k',
        0x26 => 'l',  0x27 => ';',  0x28 => '\'',
        0x29 => '`',  0x2B => '\\',
        0x2C => 'z',  0x2D => 'x',  0x2E => 'c',  0x2F => 'v',
        0x30 => 'b',  0x31 => 'n',  0x32 => 'm',  0x33 => ',',
        0x34 => '.',  0x35 => '/',
        0x39 => ' ',
        0x1D => 'l',  0x2A => 'l',
        else => 0,
    };
}
