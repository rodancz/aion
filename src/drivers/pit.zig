const port = @import("../arch/x86_64/port.zig");

const PIT_CH0: u16 = 0x40;
const PIT_CMD: u16 = 0x43;
const BASE_FREQ: u32 = 1193182;

var frequency: u32 = 0;

pub fn init(hz: u32) void {
    frequency = hz;
    const divisor = BASE_FREQ / hz;

    port.outb(PIT_CMD, 0x36);

    port.outb(PIT_CH0, @truncate(divisor & 0xFF));
    port.outb(PIT_CH0, @truncate((divisor >> 8) & 0xFF));
}

pub fn tick() void {
    // called from IRQ0 handler — nothing to do for now
}

pub fn get_frequency() u32 {
    return frequency;
}
