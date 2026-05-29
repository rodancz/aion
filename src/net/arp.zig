const e1000 = @import("../drivers/e1000.zig");

pub const MacAddr = [6]u8;

pub fn send_arp_request(target_ip: u32) void {
    var macarr: [6]u8 = undefined;
    const mac_slice = e1000.get_mac();
    for (mac_slice, 0..) |b, i| macarr[i] = b;

    var pkt: [64]u8 = [_]u8{0} ** 64;

    // Ethernet header: broadcast dst
    pkt[0] = 0xFF; pkt[1] = 0xFF; pkt[2] = 0xFF;
    pkt[3] = 0xFF; pkt[4] = 0xFF; pkt[5] = 0xFF;
    pkt[6] = macarr[0]; pkt[7] = macarr[1]; pkt[8] = macarr[2];
    pkt[9] = macarr[3]; pkt[10] = macarr[4]; pkt[11] = macarr[5];
    pkt[12] = 0x08; pkt[13] = 0x06; // ARP

    // ARP header
    pkt[14] = 0x00; pkt[15] = 0x01; // HTYPE
    pkt[16] = 0x08; pkt[17] = 0x00; // PTYPE
    pkt[18] = 6;     pkt[19] = 4;     // HLEN, PLEN
    pkt[20] = 0x00; pkt[21] = 0x01; // OPER = request

    // Sender MAC
    pkt[22] = macarr[0]; pkt[23] = macarr[1]; pkt[24] = macarr[2];
    pkt[25] = macarr[3]; pkt[26] = macarr[4]; pkt[27] = macarr[5];

    // Sender IP (10.0.2.15) — network byte order
    const my_ip: u32 = 0x0A00020F;
    pkt[28] = @truncate((my_ip >> 24) & 0xFF);
    pkt[29] = @truncate((my_ip >> 16) & 0xFF);
    pkt[30] = @truncate((my_ip >> 8) & 0xFF);
    pkt[31] = @truncate(my_ip & 0xFF);

    // Target MAC (zero)
    pkt[32] = 0; pkt[33] = 0; pkt[34] = 0; pkt[35] = 0; pkt[36] = 0; pkt[37] = 0;

    // Target IP — network byte order
    pkt[38] = @truncate((target_ip >> 24) & 0xFF);
    pkt[39] = @truncate((target_ip >> 16) & 0xFF);
    pkt[40] = @truncate((target_ip >> 8) & 0xFF);
    pkt[41] = @truncate(target_ip & 0xFF);

    _ = e1000.send_packet(pkt[0..60]); // pad to min Ethernet frame
}

pub fn handle_packet(pkt: []const u8) void {
    if (pkt.len < 42) return;
    if (pkt[12] != 0x08 or pkt[13] != 0x06) return; // not ARP
    if (pkt[20] != 0x00 or pkt[21] != 0x02) return; // not reply

    // Store gateway MAC
    gateway_mac[0] = pkt[6];
    gateway_mac[1] = pkt[7];
    gateway_mac[2] = pkt[8];
    gateway_mac[3] = pkt[9];
    gateway_mac[4] = pkt[10];
    gateway_mac[5] = pkt[11];
}

pub var gateway_mac: MacAddr = [_]u8{0} ** 6;
