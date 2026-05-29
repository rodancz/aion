extern fn asm_outb(port: u16, value: u8) void;
extern fn asm_inb(port: u16) u8;
extern fn asm_outw(port: u16, value: u16) void;
extern fn asm_inw(port: u16) u16;
extern fn asm_outl(port: u16, value: u32) void;
extern fn asm_inl(port: u16) u32;

pub inline fn outb(port: u16, value: u8) void { asm_outb(port, value); }
pub inline fn inb(port: u16) u8 { return asm_inb(port); }
pub inline fn outw(port: u16, value: u16) void { asm_outw(port, value); }
pub inline fn inw(port: u16) u16 { return asm_inw(port); }
pub inline fn outl(port: u16, value: u32) void { asm_outl(port, value); }
pub inline fn inl(port: u16) u32 { return asm_inl(port); }
