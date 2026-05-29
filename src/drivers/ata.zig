const port = @import("../arch/x86_64/port.zig");
const console = @import("console.zig");

const ATA_DATA: u16 = 0x1F0;
const ATA_ERROR: u16 = 0x1F1;
const ATA_SECTORS: u16 = 0x1F2;
const ATA_LBA_LO: u16 = 0x1F3;
const ATA_LBA_MID: u16 = 0x1F4;
const ATA_LBA_HI: u16 = 0x1F5;
const ATA_DRIVE: u16 = 0x1F6;
const ATA_STATUS: u16 = 0x1F7;
const ATA_CMD: u16 = 0x1F7;

const STATUS_BSY: u8 = 0x80;
const STATUS_DRQ: u8 = 0x08;
const STATUS_ERR: u8 = 0x01;

var drive_present: bool = false;

pub fn init() bool {
    // Select master drive
    port.outb(ATA_DRIVE, 0xA0);
    spin(1000);

    // Check if floating bus (all zeros = no drive)
    const status = port.inb(ATA_STATUS);
    if (status == 0xFF or status == 0x00) {
        console.write_str("[ATA] No drive detected");
        return false;
    }

    // Reset
    port.outb(ATA_DRIVE, 0xA0);
    spin(1000);

    // Wait for ready
    var timeout: u32 = 100000;
    while (timeout > 0) : (timeout -= 1) {
        const st = port.inb(ATA_STATUS);
        if (st & (STATUS_BSY | STATUS_ERR) == 0) break;
    }
    if (timeout == 0) {
        console.write_str("[ATA] Timeout waiting for ready");
        return false;
    }

    // Identify to get capacity
    port.outb(ATA_DRIVE, 0xA0);
    port.outb(ATA_SECTORS, 0);
    port.outb(ATA_LBA_LO, 0);
    port.outb(ATA_LBA_MID, 0);
    port.outb(ATA_LBA_HI, 0);
    port.outb(ATA_CMD, 0xEC); // IDENTIFY

    const st = port.inb(ATA_STATUS);
    if (st == 0) return false;

    // Wait for DRQ
    timeout = 100000;
    while (timeout > 0) : (timeout -= 1) {
        const st2 = port.inb(ATA_STATUS);
        if (st2 & STATUS_ERR != 0) return false;
        if (st2 & STATUS_DRQ != 0) break;
    }
    if (timeout == 0) return false;

    // Read 256 words of identify data
    var i: u16 = 0;
    while (i < 256) : (i += 1) {
        _ = port.inw(ATA_DATA);
    }

    drive_present = true;
    console.write_str("[ATA] Drive ready");
    return true;
}

pub fn read_sector(lba: u32, buf: [*]u8) bool {
    return read_sectors(lba, 1, buf);
}

pub fn write_sector(lba: u32, buf: [*]const u8) bool {
    return write_sectors(lba, 1, buf);
}

pub fn read_sectors(lba: u32, count: u8, buf: [*]u8) bool {
    if (!drive_present) return false;

    // Wait for not busy
    var timeout: u32 = 100000;
    while (timeout > 0) : (timeout -= 1) {
        if (port.inb(ATA_STATUS) & STATUS_BSY == 0) break;
    }
    if (timeout == 0) return false;

    // LBA28
    port.outb(ATA_DRIVE, 0xE0 | @as(u8, @truncate((lba >> 24) & 0x0F)));
    port.outb(ATA_SECTORS, count);
    port.outb(ATA_LBA_LO, @truncate(lba));
    port.outb(ATA_LBA_MID, @truncate(lba >> 8));
    port.outb(ATA_LBA_HI, @truncate(lba >> 16));
    port.outb(ATA_CMD, 0x20); // READ SECTORS

    var s: u8 = 0;
    while (s < count) : (s += 1) {
        // Wait for DRQ
        timeout = 100000;
        while (timeout > 0) : (timeout -= 1) {
            const st = port.inb(ATA_STATUS);
            if (st & STATUS_ERR != 0) return false;
            if (st & STATUS_DRQ != 0) break;
        }
        if (timeout == 0) return false;

        // Read 256 words (512 bytes)
        var i: u16 = 0;
        while (i < 256) : (i += 1) {
            const word = port.inw(ATA_DATA);
            const offset = @as(usize, s) * 512 + @as(usize, i) * 2;
            buf[offset] = @truncate(word);
            buf[offset + 1] = @truncate(word >> 8);
        }
    }
    return true;
}

pub fn write_sectors(lba: u32, count: u8, buf: [*]const u8) bool {
    if (!drive_present) return false;

    var timeout: u32 = 100000;
    while (timeout > 0) : (timeout -= 1) {
        if (port.inb(ATA_STATUS) & STATUS_BSY == 0) break;
    }
    if (timeout == 0) return false;

    port.outb(ATA_DRIVE, 0xE0 | @as(u8, @truncate((lba >> 24) & 0x0F)));
    port.outb(ATA_SECTORS, count);
    port.outb(ATA_LBA_LO, @truncate(lba));
    port.outb(ATA_LBA_MID, @truncate(lba >> 8));
    port.outb(ATA_LBA_HI, @truncate(lba >> 16));
    port.outb(ATA_CMD, 0x30); // WRITE SECTORS

    var s: u8 = 0;
    while (s < count) : (s += 1) {
        timeout = 100000;
        while (timeout > 0) : (timeout -= 1) {
            if (port.inb(ATA_STATUS) & STATUS_DRQ != 0) break;
        }
        if (timeout == 0) return false;

        var i: u16 = 0;
        while (i < 256) : (i += 1) {
            const offset = @as(usize, s) * 512 + @as(usize, i) * 2;
            const word: u16 = (@as(u16, buf[offset + 1]) << 8) | buf[offset];
            port.outw(ATA_DATA, word);
        }
    }

    // Flush cache
    port.outb(ATA_CMD, 0xE7);
    timeout = 100000;
    while (timeout > 0) : (timeout -= 1) {
        if (port.inb(ATA_STATUS) & STATUS_BSY == 0) break;
    }

    return true;
}

fn spin(n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {}
}
