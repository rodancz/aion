const e1000 = @import("../drivers/e1000.zig");
const arp = @import("arp.zig");

pub var my_ip: u32 = 0x0A00020F; // 10.0.2.15 default, updated by DHCP
pub var gateway_ip: u32 = 0x0A000202;
pub var dns_ip: u32 = 0x0A000203;

pub fn send_udp(dst_ip: u32, src_port: u16, dst_port: u16, payload: []const u8) bool {
    const total_len: u16 = @truncate(28 + payload.len);
    var buf: [2048]u8 = [_]u8{0} ** 2048;

    const mac_slice = e1000.get_mac();
    buf[0] = arp.gateway_mac[0]; buf[1] = arp.gateway_mac[1];
    buf[2] = arp.gateway_mac[2]; buf[3] = arp.gateway_mac[3];
    buf[4] = arp.gateway_mac[4]; buf[5] = arp.gateway_mac[5];
    buf[6] = mac_slice[0]; buf[7] = mac_slice[1];
    buf[8] = mac_slice[2]; buf[9] = mac_slice[3];
    buf[10] = mac_slice[4]; buf[11] = mac_slice[5];
    buf[12] = 0x08; buf[13] = 0x00;

    // IP header
    buf[14] = 0x45;
    buf[15] = 0;
    buf[16] = @truncate(total_len >> 8);
    buf[17] = @truncate(total_len & 0xFF);
    buf[18] = 0; buf[19] = 0;
    buf[20] = 0; buf[21] = 0;
    buf[22] = 64;
    buf[23] = 17; // UDP

    buf[24] = 0; buf[25] = 0;

    // Src IP (network byte order)
    buf[26] = @truncate((my_ip >> 24) & 0xFF);
    buf[27] = @truncate((my_ip >> 16) & 0xFF);
    buf[28] = @truncate((my_ip >> 8) & 0xFF);
    buf[29] = @truncate(my_ip & 0xFF);

    // Dst IP (network byte order)
    buf[30] = @truncate((dst_ip >> 24) & 0xFF);
    buf[31] = @truncate((dst_ip >> 16) & 0xFF);
    buf[32] = @truncate((dst_ip >> 8) & 0xFF);
    buf[33] = @truncate(dst_ip & 0xFF);

    // IP checksum
    var ip_sum: u32 = 0;
    var i: usize = 14;
    while (i < 34) : (i += 2) {
        const word: u16 = (@as(u16, buf[i]) << 8) | buf[i + 1];
        ip_sum += word;
    }
    while (ip_sum > 0xFFFF) {
        ip_sum = (ip_sum & 0xFFFF) + (ip_sum >> 16);
    }
    const ip_cksum: u16 = @truncate(~ip_sum & 0xFFFF);
    buf[24] = @truncate(ip_cksum >> 8);
    buf[25] = @truncate(ip_cksum & 0xFF);

    // UDP header
    const udp_len: u16 = @truncate(8 + payload.len);
    buf[34] = @truncate(src_port >> 8); buf[35] = @truncate(src_port & 0xFF);
    buf[36] = @truncate(dst_port >> 8); buf[37] = @truncate(dst_port & 0xFF);
    buf[38] = @truncate(udp_len >> 8); buf[39] = @truncate(udp_len & 0xFF);
    buf[40] = 0; buf[41] = 0;

    i = 0;
    while (i < payload.len) : (i += 1) {
        buf[42 + i] = payload[i];
    }

    return e1000.send_packet(buf[0 .. 42 + payload.len]);
}

pub fn send_udp_broadcast(dst_ip: u32, src_port: u16, dst_port: u16, payload: []const u8) bool {
    const total_len: u16 = @truncate(28 + payload.len);
    var buf: [2048]u8 = [_]u8{0} ** 2048;

    // Broadcast Ethernet
    const mac_slice = e1000.get_mac();
    buf[0] = 0xFF; buf[1] = 0xFF; buf[2] = 0xFF;
    buf[3] = 0xFF; buf[4] = 0xFF; buf[5] = 0xFF;
    buf[6] = mac_slice[0]; buf[7] = mac_slice[1];
    buf[8] = mac_slice[2]; buf[9] = mac_slice[3];
    buf[10] = mac_slice[4]; buf[11] = mac_slice[5];
    buf[12] = 0x08; buf[13] = 0x00;

    buf[14] = 0x45; buf[15] = 0;
    buf[16] = @truncate(total_len >> 8);
    buf[17] = @truncate(total_len & 0xFF);
    buf[18] = 0; buf[19] = 0;
    buf[20] = 0; buf[21] = 0;
    buf[22] = 64;
    buf[23] = 17;

    buf[24] = 0; buf[25] = 0;

    // Src IP = 0.0.0.0 for DHCP
    buf[26] = 0; buf[27] = 0; buf[28] = 0; buf[29] = 0;

    // Dst IP
    buf[30] = @truncate(dst_ip & 0xFF);
    buf[31] = @truncate((dst_ip >> 8) & 0xFF);
    buf[32] = @truncate((dst_ip >> 16) & 0xFF);
    buf[33] = @truncate((dst_ip >> 24) & 0xFF);

    var ip_sum: u32 = 0;
    var i: usize = 14;
    while (i < 34) : (i += 2) {
        const word: u16 = (@as(u16, buf[i]) << 8) | buf[i + 1];
        ip_sum += word;
    }
    while (ip_sum > 0xFFFF) {
        ip_sum = (ip_sum & 0xFFFF) + (ip_sum >> 16);
    }
    const ip_cksum: u16 = @truncate(~ip_sum & 0xFFFF);
    buf[24] = @truncate(ip_cksum >> 8);
    buf[25] = @truncate(ip_cksum & 0xFF);

    const udp_len: u16 = @truncate(8 + payload.len);
    buf[34] = @truncate(src_port >> 8); buf[35] = @truncate(src_port & 0xFF);
    buf[36] = @truncate(dst_port >> 8); buf[37] = @truncate(dst_port & 0xFF);
    buf[38] = @truncate(udp_len >> 8); buf[39] = @truncate(udp_len & 0xFF);
    buf[40] = 0; buf[41] = 0;

    i = 0;
    while (i < payload.len) : (i += 1) {
        buf[42 + i] = payload[i];
    }

    return e1000.send_packet(buf[0 .. 42 + payload.len]);
}

pub fn handle_packet(pkt: []const u8) void {
    if (pkt.len < 42) return;
    if (pkt[12] != 0x08 or pkt[13] != 0x00) return;
    if (pkt[23] != 17) return;

    // Check if this is for us
    const dst_ip = (@as(u32, pkt[30]) << 24) | (@as(u32, pkt[31]) << 16) | (@as(u32, pkt[32]) << 8) | pkt[33];
    if (dst_ip != my_ip and dst_ip != 0xFFFFFFFF and my_ip != 0) return;

    // Extract UDP src/dst ports
    const src_port = (@as(u16, pkt[34]) << 8) | pkt[35];
    const dst_port = (@as(u16, pkt[36]) << 8) | pkt[37];

    // Store for registered handlers
    const data_start: usize = 42;
    if (pkt.len > data_start) {
        const data_len = pkt.len - data_start;
        udp_rx_src_port = src_port;
        udp_rx_dst_port = dst_port;
        var k: usize = 0;
        while (k < data_len and k < udp_rx_buf.len) : (k += 1) {
            udp_rx_buf[k] = pkt[data_start + k];
        }
        udp_rx_len = data_len;
        udp_have_data = true;
    }
}

var udp_rx_buf: [2048]u8 = [_]u8{0} ** 2048;
var udp_rx_len: usize = 0;
var udp_have_data: bool = false;
var udp_rx_src_port: u16 = 0;
var udp_rx_dst_port: u16 = 0;

pub fn receive(buf: []u8) ?struct { len: usize, src_port: u16, dst_port: u16 } {
    if (!udp_have_data) return null;
    const len = udp_rx_len;
    if (len > buf.len) return null;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        buf[i] = udp_rx_buf[i];
    }
    udp_have_data = false;
    return .{ .len = len, .src_port = udp_rx_src_port, .dst_port = udp_rx_dst_port };
}
