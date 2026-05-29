const port = @import("../arch/x86_64/port.zig");

const PCI_ADDR: u16 = 0xCF8;
const PCI_DATA: u16 = 0xCFC;

pub const PCIDevice = struct {
    bus: u8,
    device: u8,
    function: u8,
    vendor_id: u16,
    device_id: u16,
    class_code: u8,
    subclass: u8,
    bar0: u32,
    bar1: u32,
};

fn read32(bus: u8, device: u8, func: u8, offset: u8) u32 {
    const addr: u32 = (@as(u32, 1) << 31) |
        (@as(u32, bus) << 16) |
        (@as(u32, device) << 11) |
        (@as(u32, func) << 8) |
        (@as(u32, offset) & 0xFC);
    port.outl(PCI_ADDR, addr);
    return port.inl(PCI_DATA);
}

fn read16(bus: u8, device: u8, func: u8, offset: u8) u16 {
    return @truncate(read32(bus, device, func, offset) >> @as(u5, @truncate((offset & 2) * 8)));
}

fn write16(bus: u8, device: u8, func: u8, offset: u8, value: u16) void {
    const addr: u32 = (@as(u32, 1) << 31) |
        (@as(u32, bus) << 16) |
        (@as(u32, device) << 11) |
        (@as(u32, func) << 8) |
        (@as(u32, offset) & 0xFC);
    port.outl(PCI_ADDR, addr);
    const old = port.inl(PCI_DATA);
    const shift: u5 = @truncate((offset & 2) * 8);
    const mask: u32 = @as(u32, 0xFFFF) << shift;
    const new_val = (old & ~mask) | (@as(u32, value) << shift);
    port.outl(PCI_ADDR, addr);
    port.outl(PCI_DATA, new_val);
}

pub fn enable_device(dev: PCIDevice) void {
    var cmd = read16(dev.bus, dev.device, dev.function, 4);
    cmd |= (1 << 2) | (1 << 1);
    write16(dev.bus, dev.device, dev.function, 4, cmd);
}

pub fn scan() ?PCIDevice {
    var dev: u8 = 0;
    while (dev < 32) : (dev += 1) {
        const vendor = read16(0, dev, 0, 0);
        if (vendor == 0xFFFF) continue;

        const device_id = read16(0, dev, 0, 2);
        const class_subclass = read32(0, dev, 0, 8);
        const class_code: u8 = @truncate((class_subclass >> 24) & 0xFF);
        const subclass: u8 = @truncate((class_subclass >> 16) & 0xFF);

        if (class_code == 0x02 and subclass == 0x00) {
            const bar0 = read32(0, dev, 0, 0x10);
            const bar1 = read32(0, dev, 0, 0x14);
            // Accept Intel e1000 (8086), e1000e (8086), I219 (8086), and others
            if (vendor == 0x8086) {
                return PCIDevice{
                    .bus = 0, .device = dev, .function = 0,
                    .vendor_id = vendor, .device_id = device_id,
                    .class_code = class_code, .subclass = subclass,
                    .bar0 = bar0, .bar1 = bar1,
                };
            }
        }
    }
    return null;
}
