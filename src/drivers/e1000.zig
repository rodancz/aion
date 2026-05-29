const pmm = @import("../core/pmm.zig");
const console = @import("../drivers/console.zig");

const REG_CTRL: usize = 0x0000;
const REG_STATUS: usize = 0x0008;
const REG_EERD: usize = 0x0014;
const REG_IMS: usize = 0x00D0;
const REG_ICR: usize = 0x00C0;
const REG_RCTL: usize = 0x0100;
const REG_TCTL: usize = 0x0400;
const REG_RDBAL: usize = 0x2800;
const REG_RDBAH: usize = 0x2804;
const REG_RDLEN: usize = 0x2808;
const REG_RDH: usize = 0x2810;
const REG_RDT: usize = 0x2818;
const REG_TDBAL: usize = 0x3800;
const REG_TDBAH: usize = 0x3804;
const REG_TDLEN: usize = 0x3808;
const REG_TDH: usize = 0x3810;
const REG_TDT: usize = 0x3818;

const RX_DESC_COUNT: usize = 32;
const TX_DESC_COUNT: usize = 8;

var mmio_base: usize = 0;
var ready: bool = false;
var rx_desc: [*]volatile u64 = undefined;
var tx_desc: [*]volatile u64 = undefined;
var tx_buffers: [*]volatile u8 = undefined;
var rx_tail: usize = 0;
var mac: [6]u8 = [_]u8{0} ** 6;
var tx_buf_offset: usize = 0;

fn reg_read(reg: usize) u32 {
    const ptr: *volatile u32 = @ptrFromInt(mmio_base + reg);
    return ptr.*;
}

fn reg_write(reg: usize, val: u32) void {
    const ptr: *volatile u32 = @ptrFromInt(mmio_base + reg);
    ptr.* = val;
}

pub fn init(bar0: u32, bar1: u32) bool {
    _ = bar1;
    mmio_base = bar0 & 0xFFFFFFF0;

    reg_write(REG_CTRL, (1 << 26));
    var rst_timeout: u32 = 100000;
    while ((reg_read(REG_CTRL) & (1 << 26)) != 0 and rst_timeout > 0) : (rst_timeout -= 1) {}

    var ctrl = reg_read(REG_CTRL);
    ctrl |= (1 << 5) | (1 << 6);
    reg_write(REG_CTRL, ctrl);

    var link_timeout: u32 = 500000;
    while ((reg_read(REG_STATUS) & (1 << 1)) == 0 and link_timeout > 0) : (link_timeout -= 1) {}
    if (link_timeout == 0) return false;

    const status = reg_read(REG_STATUS);
    _ = status;

    const ral = reg_read(0x5400);
    const rah = reg_read(0x5404);
    mac[0] = @truncate(ral & 0xFF);
    mac[1] = @truncate((ral >> 8) & 0xFF);
    mac[2] = @truncate((ral >> 16) & 0xFF);
    mac[3] = @truncate((ral >> 24) & 0xFF);
    mac[4] = @truncate(rah & 0xFF);
    mac[5] = @truncate((rah >> 8) & 0xFF);

    reg_write(0x5400, ral);
    reg_write(0x5404, rah | (1 << 31));

    reg_write(REG_IMS, 0);

    const rx_desc_phys = pmm.alloc_frame() orelse return false;
    rx_desc = @ptrFromInt(rx_desc_phys);
    var j: usize = 0;
    while (j < RX_DESC_COUNT * 2) : (j += 1) { rx_desc[j] = 0; }

    var rx_buf_addrs: [RX_DESC_COUNT]usize = undefined;
    {
        var bp: usize = 0;
        while (bp < RX_DESC_COUNT) : (bp += 1) {
            rx_buf_addrs[bp] = pmm.alloc_frame() orelse return false;
        }
    }

    j = 0;
    while (j < RX_DESC_COUNT) : (j += 1) {
        rx_desc[j * 2] = rx_buf_addrs[j];
        rx_desc[j * 2 + 1] = 0;
    }

    reg_write(REG_RDBAL, @truncate(rx_desc_phys));
    reg_write(REG_RDBAH, 0);
    reg_write(REG_RDLEN, @as(u32, @truncate(RX_DESC_COUNT * 16)));
    reg_write(REG_RDH, 0);
    reg_write(REG_RDT, @as(u32, @truncate(RX_DESC_COUNT - 1)));
    rx_tail = 0;

    const tx_desc_phys = pmm.alloc_frame() orelse return false;
    tx_desc = @ptrFromInt(tx_desc_phys);
    j = 0;
    while (j < TX_DESC_COUNT * 2) : (j += 1) { tx_desc[j] = 0; }

    tx_buffers = @ptrFromInt(pmm.alloc_frame() orelse return false);

    reg_write(REG_TDBAL, @truncate(tx_desc_phys));
    reg_write(REG_TDBAH, 0);
    reg_write(REG_TDLEN, @as(u32, @truncate(TX_DESC_COUNT * 16)));
    reg_write(REG_TDH, 0);
    reg_write(REG_TDT, 0);

    reg_write(REG_TCTL, (1 << 1) | (1 << 3) | (15 << 4) | (64 << 12));

    const rctl_val = reg_read(REG_RCTL);
    const status_val = reg_read(REG_STATUS);
    _ = rctl_val;
    _ = status_val;

    reg_write(REG_RCTL, (1 << 1) | (1 << 2) | (1 << 3) | (1 << 4) | (1 << 26));

    {
        var mi: u32 = 0;
        while (mi < 128) : (mi += 1) {
            reg_write(0x5200 + @as(usize, mi) * 4, 0xFFFFFFFF);
        }
    }

    tx_buf_offset = 0;
    ready = true;
    console.write_str("[E1000] NIC initialized");
    return true;
}

pub fn get_mac() []const u8 {
    return &mac;
}

pub fn send_packet(data: []const u8) bool {
    if (!ready) return false;
    const tx_idx: usize = reg_read(REG_TDT);

    const buf_start = tx_buf_offset;
    tx_buf_offset += 2048;
    if (tx_buf_offset >= 4096) tx_buf_offset = 0;

    var i: usize = 0;
    while (i < data.len and i < 2048) : (i += 1) {
        tx_buffers[buf_start + i] = data[i];
    }

    tx_desc[tx_idx * 2] = @intFromPtr(&tx_buffers[buf_start]);
    tx_desc[tx_idx * 2 + 1] = @as(u64, data.len) | (1 << 24) | (1 << 25) | (1 << 27);

    const new_idx = (tx_idx + 1) % TX_DESC_COUNT;
    reg_write(REG_TDT, @as(u32, @truncate(new_idx)));

    var timeout: u32 = 100000;
    while (timeout > 0) : (timeout -= 1) {
        if (tx_desc[tx_idx * 2 + 1] & (@as(u64, 1) << 32) != 0) break;
    }
    if (timeout == 0) return false;

    return true;
}

pub fn receive_packet(buf: []u8) ?usize {
    if (!ready) return null;
    if ((rx_desc[rx_tail * 2 + 1] >> 32) & 1 == 0) return null;

    const len: usize = @truncate(rx_desc[rx_tail * 2 + 1] & 0x3FFF);
    if (len > 0 and len <= buf.len) {
        const src_addr = rx_desc[rx_tail * 2] & 0xFFFFFFFF;
        const src: [*]const u8 = @ptrFromInt(@as(usize, @truncate(src_addr)));
        var i: usize = 0;
        while (i < len) : (i += 1) buf[i] = src[i];
    }

    rx_desc[rx_tail * 2 + 1] = 0;
    rx_tail = (rx_tail + 1) % RX_DESC_COUNT;
    reg_write(REG_RDT, @as(u32, @truncate((rx_tail + RX_DESC_COUNT - 1) % RX_DESC_COUNT)));

    return len;
}
