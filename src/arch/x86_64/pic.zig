const port = @import("port.zig");

const PIC1_CMD: u16 = 0x20;
const PIC1_DATA: u16 = 0x21;
const PIC2_CMD: u16 = 0xA0;
const PIC2_DATA: u16 = 0xA1;

const ICW1_INIT: u8 = 0x11;
const ICW4_8086: u8 = 0x01;

pub fn init() void {
    port.outb(PIC1_CMD, ICW1_INIT);
    port.outb(PIC1_DATA, 0x20);
    port.outb(PIC1_DATA, 0x04);
    port.outb(PIC1_DATA, ICW4_8086);

    port.outb(PIC2_CMD, ICW1_INIT);
    port.outb(PIC2_DATA, 0x28);
    port.outb(PIC2_DATA, 0x02);
    port.outb(PIC2_DATA, ICW4_8086);

    port.outb(PIC1_DATA, 0xFF);
    port.outb(PIC2_DATA, 0xFF);
}

pub fn send_eoi(irq: u8) void {
    if (irq >= 8) {
        port.outb(PIC2_CMD, 0x20);
    }
    port.outb(PIC1_CMD, 0x20);
}

pub fn unmask(irq: u8) void {
    var port_addr: u16 = PIC1_DATA;
    if (irq >= 8) {
        port_addr = PIC2_DATA;
    }
    const val = port.inb(port_addr) & ~(@as(u8, 1) << @as(u3, @truncate(irq % 8)));
    port.outb(port_addr, val);
}
