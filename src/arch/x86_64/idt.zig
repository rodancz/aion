extern fn asm_lidt(ptr: *const volatile IDTPtr) void;

extern fn except0() void;
extern fn except1() void;
extern fn except2() void;
extern fn except3() void;
extern fn except4() void;
extern fn except5() void;
extern fn except6() void;
extern fn except7() void;
extern fn except8() void;
extern fn except9() void;
extern fn except10() void;
extern fn except11() void;
extern fn except12() void;
extern fn except13() void;
extern fn except14() void;
extern fn except15() void;
extern fn except16() void;
extern fn except17() void;
extern fn except18() void;
extern fn except19() void;
extern fn except20() void;
extern fn except21() void;
extern fn except22() void;
extern fn except23() void;
extern fn except24() void;
extern fn except25() void;
extern fn except26() void;
extern fn except27() void;
extern fn except28() void;
extern fn except29() void;
extern fn except30() void;
extern fn except31() void;

extern fn irq0() void;
extern fn irq1() void;
extern fn irq2() void;
extern fn irq3() void;
extern fn irq4() void;
extern fn irq5() void;
extern fn irq6() void;
extern fn irq7() void;
extern fn irq8() void;
extern fn irq9() void;
extern fn irq10() void;
extern fn irq11() void;
extern fn irq12() void;
extern fn irq13() void;
extern fn irq14() void;
extern fn irq15() void;

const IDTEntry = extern struct {
    offset_low: u16,
    selector: u16,
    ist:  u8,
    type_attr: u8,
    offset_mid: u16,
    offset_high: u32,
    reserved: u32,
};

const IDTPtr = packed struct {
    limit: u16,
    base: u64,
};

const IDT_SIZE: u16 = 256;

const except_handlers = [_]*const fn () callconv(.c) void{
    &except0,  &except1,  &except2,  &except3,
    &except4,  &except5,  &except6,  &except7,
    &except8,  &except9,  &except10, &except11,
    &except12, &except13, &except14, &except15,
    &except16, &except17, &except18, &except19,
    &except20, &except21, &except22, &except23,
    &except24, &except25, &except26, &except27,
    &except28, &except29, &except30, &except31,
};

const irq_handlers = [_]*const fn () callconv(.c) void{
    &irq0,  &irq1,  &irq2,  &irq3,
    &irq4,  &irq5,  &irq6,  &irq7,
    &irq8,  &irq9,  &irq10, &irq11,
    &irq12, &irq13, &irq14, &irq15,
};

var idt: [IDT_SIZE]IDTEntry = [_]IDTEntry{
    IDTEntry{
        .offset_low = 0,
        .selector = 0,
        .ist = 0,
        .type_attr = 0,
        .offset_mid = 0,
        .offset_high = 0,
        .reserved = 0,
    },
} ** IDT_SIZE;

fn set_entry(vector: u8, handler: usize, dpl: u8, ist: u8) void {
    idt[vector] = IDTEntry{
        .offset_low = @as(u16, @truncate(handler)),
        .selector = 0x08,
        .ist = ist,
        .type_attr = 0x8E | (dpl << 5),
        .offset_mid = @as(u16, @truncate(handler >> 16)),
        .offset_high = @as(u32, @truncate(handler >> 32)),
        .reserved = 0,
    };
}

pub fn init() void {
    for (except_handlers, 0..) |handler, i| {
        set_entry(@truncate(i), @intFromPtr(handler), 0, 0);
    }

    for (irq_handlers, 0..) |handler, i| {
        set_entry(@truncate(i + 32), @intFromPtr(handler), 0, 0);
    }

    const ptr = IDTPtr{
        .limit = @sizeOf(@TypeOf(idt)) - 1,
        .base = @intFromPtr(&idt),
    };
    asm_lidt(&ptr);
}
