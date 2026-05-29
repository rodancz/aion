extern fn asm_lgdt(ptr: *const volatile GDTPtr) void;

const GDTEntry = extern struct {
    limit_low: u16,
    base_low: u16,
    base_mid: u8,
    access: u8,
    limit_high_flags: u8,
    base_high: u8,
};

const GDTPtr = packed struct {
    limit: u16,
    base: u64,
};

var gdt: [5]GDTEntry = [_]GDTEntry{
    GDTEntry{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0, .limit_high_flags = 0, .base_high = 0 },
    GDTEntry{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x9A, .limit_high_flags = 0x20, .base_high = 0 },
    GDTEntry{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0x92, .limit_high_flags = 0x00, .base_high = 0 },
    GDTEntry{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0xFA, .limit_high_flags = 0x20, .base_high = 0 },
    GDTEntry{ .limit_low = 0, .base_low = 0, .base_mid = 0, .access = 0xF2, .limit_high_flags = 0x00, .base_high = 0 },
};

pub fn init() void {
    const ptr = GDTPtr{
        .limit = @sizeOf(@TypeOf(gdt)) - 1,
        .base = @intFromPtr(&gdt),
    };
    asm_lgdt(&ptr);
}
