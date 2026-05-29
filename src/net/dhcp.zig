const udp = @import("udp.zig");
const console = @import("../drivers/console.zig");

pub const DhcpConfig = struct {
    ip: u32,
    netmask: u32,
    gateway: u32,
    dns: u32,
    server: u32,
    lease: u32,
    configured: bool,
};

pub var config: DhcpConfig = DhcpConfig{
    .ip = 0,
    .netmask = 0,
    .gateway = 0x0A000202,
    .dns = 0x01010101, // 1.1.1.1 direct
    .server = 0,
    .lease = 0,
    .configured = false,
};

var xid: u32 = 0;
var state: enum { idle, discover_sent, offer_recv, request_sent, done } = .idle;
var retry_ticks: u64 = 0;

pub fn start() void {
    const t = @import("../arch/x86_64/isr.zig").get_ticks();
    xid = @truncate(t);
    state = .discover_sent;
    retry_ticks = 0;
    send_discover();
    console.write_str("[DHCP] Discover sent");
}

pub fn tick() void {
    switch (state) {
        .discover_sent => {
            retry_ticks += 1;
            if (retry_ticks > 300) {
                retry_ticks = 0;
                send_discover();
                console.write_str("[DHCP] Retry discover");
            }
        },
        .offer_recv => {
            retry_ticks += 1;
            if (retry_ticks > 300) {
                state = .idle;
                console.write_str("[DHCP] Offer timeout");
            }
        },
        .request_sent => {
            retry_ticks += 1;
            if (retry_ticks > 300) {
                retry_ticks = 0;
                send_request();
                console.write_str("[DHCP] Retry request");
            }
        },
        .done, .idle => {},
    }
}

fn send_discover() void {
    var pkt: [576]u8 = [_]u8{0} ** 576;

    pkt[0] = 1; // BOOTREQUEST
    pkt[1] = 1; // HTYPE Ethernet
    pkt[2] = 6; // HLEN
    pkt[3] = 0; // HOPS
    pkt[4] = @truncate(xid >> 24);
    pkt[5] = @truncate(xid >> 16);
    pkt[6] = @truncate(xid >> 8);
    pkt[7] = @truncate(xid);
    // secs, flags, ciaddr, yiaddr, siaddr, giaddr = 0
    // chaddr (MAC) - leave zero for now, hardware fills broadcast
    // But we need a MAC - copy from e1000
    const mac = @import("../drivers/e1000.zig").get_mac();
    pkt[28] = mac[0]; pkt[29] = mac[1]; pkt[30] = mac[2];
    pkt[31] = mac[3]; pkt[32] = mac[4]; pkt[33] = mac[5];

    // DHCP magic cookie at options offset 236 (after 44 header + 64 sname + 128 file)
    var i: usize = 236;
    pkt[i] = 99; i += 1; // 0x63
    pkt[i] = 130; i += 1; // 0x82
    pkt[i] = 83; i += 1; // 0x53
    pkt[i] = 99; i += 1; // 0x63

    // DHCP option 53: DHCPDISCOVER
    pkt[i] = 53; i += 1; pkt[i] = 1; i += 1; pkt[i] = 1; i += 1;
    // DHCP option 55: parameter request list
    pkt[i] = 55; i += 1; pkt[i] = 4; i += 1;
    pkt[i] = 1;  i += 1; // subnet mask
    pkt[i] = 3;  i += 1; // router
    pkt[i] = 6;  i += 1; // DNS
    pkt[i] = 51; i += 1; // lease time
    // DHCP option 255: END
    pkt[i] = 255; i += 1;

    _ = udp.send_udp_broadcast(0xFFFFFFFF, 68, 67, pkt[0..i]);
}

fn send_request() void {
    var pkt: [576]u8 = [_]u8{0} ** 576;

    pkt[0] = 1; // BOOTREQUEST
    pkt[1] = 1; pkt[2] = 6; pkt[3] = 0;
    pkt[4] = @truncate(xid >> 24);
    pkt[5] = @truncate(xid >> 16);
    pkt[6] = @truncate(xid >> 8);
    pkt[7] = @truncate(xid);

    const mac = @import("../drivers/e1000.zig").get_mac();
    pkt[28] = mac[0]; pkt[29] = mac[1]; pkt[30] = mac[2];
    pkt[31] = mac[3]; pkt[32] = mac[4]; pkt[33] = mac[5];

    // Requested IP
    pkt[16] = @truncate(config.ip >> 24);
    pkt[17] = @truncate(config.ip >> 16);
    pkt[18] = @truncate(config.ip >> 8);
    pkt[19] = @truncate(config.ip);

    // Server IP
    pkt[20] = @truncate(config.server >> 24);
    pkt[21] = @truncate(config.server >> 16);
    pkt[22] = @truncate(config.server >> 8);
    pkt[23] = @truncate(config.server);

    var i: usize = 236;
    pkt[i] = 99; i += 1; pkt[i] = 130; i += 1; pkt[i] = 83; i += 1; pkt[i] = 99; i += 1;
    // DHCP option 53: DHCPREQUEST
    pkt[i] = 53; i += 1; pkt[i] = 1; i += 1; pkt[i] = 3; i += 1;
    // DHCP option 50: requested IP
    pkt[i] = 50; i += 1; pkt[i] = 4; i += 1;
    pkt[i] = @truncate(config.ip >> 24); i += 1;
    pkt[i] = @truncate(config.ip >> 16); i += 1;
    pkt[i] = @truncate(config.ip >> 8); i += 1;
    pkt[i] = @truncate(config.ip); i += 1;
    // DHCP option 54: server identifier
    pkt[i] = 54; i += 1; pkt[i] = 4; i += 1;
    pkt[i] = @truncate(config.server >> 24); i += 1;
    pkt[i] = @truncate(config.server >> 16); i += 1;
    pkt[i] = @truncate(config.server >> 8); i += 1;
    pkt[i] = @truncate(config.server); i += 1;
    // END
    pkt[i] = 255; i += 1;

    _ = udp.send_udp_broadcast(0xFFFFFFFF, 68, 67, pkt[0..i]);
}

pub fn handle_packet(raw_pkt: []const u8) void {
    // Skip Ethernet (14) + IP (20) + UDP (8) headers
    if (raw_pkt.len < 282) return;
    const pkt = raw_pkt[42..];
    if (pkt[0] != 2) return; // not BOOTREPLY
    const pkt_xid = (@as(u32, pkt[4]) << 24) | (@as(u32, pkt[5]) << 16) | (@as(u32, pkt[6]) << 8) | pkt[7];
    if (pkt_xid != xid) return;

    // yiaddr (offset 16 in BOOTP, but we're already at BOOTP offset)
    const yiaddr = (@as(u32, pkt[16]) << 24) | (@as(u32, pkt[17]) << 16) | (@as(u32, pkt[18]) << 8) | pkt[19];
    // siaddr
    const siaddr = (@as(u32, pkt[20]) << 24) | (@as(u32, pkt[21]) << 16) | (@as(u32, pkt[22]) << 8) | pkt[23];

    // Parse options at BOOTP offset 240
    var i: usize = 240;
    var msg_type: u8 = 0;
    var subnet_mask: u32 = 0;
    var router: u32 = 0;
    var dns: u32 = 0;
    var lease: u32 = 0;

    while (i < pkt.len - 1) {
        const opt = pkt[i];
        if (opt == 255) break;
        if (opt == 0) { i += 1; continue; }
        i += 1;
        if (i >= pkt.len) break;
        const len = pkt[i];
        i += 1;
        if (len == 0) continue;

        switch (opt) {
            53 => { if (len >= 1) msg_type = pkt[i]; },
            1 => { if (len >= 4) subnet_mask = (@as(u32, pkt[i]) << 24) | (@as(u32, pkt[i+1]) << 16) | (@as(u32, pkt[i+2]) << 8) | pkt[i+3]; },
            3 => { if (len >= 4) router = (@as(u32, pkt[i]) << 24) | (@as(u32, pkt[i+1]) << 16) | (@as(u32, pkt[i+2]) << 8) | pkt[i+3]; },
            6 => { if (len >= 4) dns = (@as(u32, pkt[i]) << 24) | (@as(u32, pkt[i+1]) << 16) | (@as(u32, pkt[i+2]) << 8) | pkt[i+3]; },
            51 => { if (len >= 4) lease = (@as(u32, pkt[i]) << 24) | (@as(u32, pkt[i+1]) << 16) | (@as(u32, pkt[i+2]) << 8) | pkt[i+3]; },
            else => {},
        }
        i += len;
    }

    switch (msg_type) {
        2 => { // DHCPOFFER
            if (state == .discover_sent) {
                config.ip = yiaddr;
                config.server = siaddr;
                if (subnet_mask != 0) config.netmask = subnet_mask;
                state = .offer_recv;
                retry_ticks = 0;
                console.write_str("[DHCP] Offer received");

                // Immediately request
                send_request();
                state = .request_sent;
                retry_ticks = 0;
                console.write_str("[DHCP] Request sent");
            }
        },
        5 => { // DHCPACK
            if (state == .request_sent) {
                config.ip = yiaddr;
                config.netmask = subnet_mask;
                config.gateway = router;
                config.dns = if (dns != 0) dns else config.dns;
                config.lease = lease;
                config.server = siaddr;
                config.configured = true;
                state = .done;

                // Sync to UDP module
                udp.my_ip = config.ip;
                udp.gateway_ip = config.gateway;
                udp.dns_ip = config.dns;

                console.write_str("[DHCP] ACK - configured");
            }
        },
        else => {},
    }
}

pub fn is_done() bool {
    return state == .done;
}
