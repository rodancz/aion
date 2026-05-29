const udp = @import("udp.zig");
const console = @import("../drivers/console.zig");

pub fn resolve(hostname: []const u8) ?u32 {
    if (udp.dns_ip == 0) return null;

    var query: [512]u8 = [_]u8{0} ** 512;
    const txid: u16 = 0xCAFE;

    query[0] = @truncate(txid >> 8);
    query[1] = @truncate(txid);
    query[2] = 1; query[3] = 0;
    query[4] = 0; query[5] = 1;
    query[6] = 0; query[7] = 0;
    query[8] = 0; query[9] = 0;
    query[10] = 0; query[11] = 0;

    var qi: usize = 12;
    var hi: usize = 0;
    while (hi < hostname.len) {
        const start = hi;
        while (hi < hostname.len and hostname[hi] != '.') : (hi += 1) {}
        const len = hi - start;
        query[qi] = @truncate(len); qi += 1;
        var j: usize = 0;
        while (j < len) : (j += 1) { query[qi] = hostname[start + j]; qi += 1; }
        if (hi < hostname.len and hostname[hi] == '.') hi += 1;
    }
    query[qi] = 0; qi += 1;
    query[qi] = 0; qi += 1; query[qi] = 1; qi += 1; // A
    query[qi] = 0; qi += 1; query[qi] = 1; qi += 1; // IN

    // Flush stale UDP
    var flush_buf: [2048]u8 = undefined;
    process_rx();
    _ = udp.receive(flush_buf[0..]);

    if (!udp.send_udp(udp.dns_ip, 1025, 53, query[0..qi])) return null;

    var ticks: u64 = 0;
    var rx_buf: [2048]u8 = undefined;
    while (ticks < 300) : (ticks += 1) {
        process_rx();
        if (udp.receive(rx_buf[0..])) |rx| {
            if (rx.src_port != 53) continue;

            // Debug: dump response header
            const rflags = (@as(u16, rx_buf[2]) << 8) | rx_buf[3];
            const ancount = (@as(u16, rx_buf[6]) << 8) | rx_buf[7];

            if ((rflags & 0x8000) == 0) {
                console.write_str("[DNS] not a response");
                continue;
            }
            if (ancount == 0) {
                console.write_str("[DNS] no answers");
                return null;
            }

            console.write_str("[DNS] parsing answer...");

            // Skip question section
            var ai: usize = 12;
            if (ai < rx.len) {
                if ((rx_buf[ai] & 0xC0) == 0xC0) {
                    ai += 2;
                } else {
                    while (ai < rx.len and rx_buf[ai] != 0) : (ai += 1) {}
                    ai += 1;
                }
            }
            ai += 4; // QTYPE + QCLASS

            if (ai + 12 > rx.len) continue;

            // Parse answer name (may be compressed pointer)
            if ((rx_buf[ai] & 0xC0) == 0xC0) ai += 2
            else { while (ai < rx.len and rx_buf[ai] != 0) : (ai += 1) {} ai += 1; }

            if (ai + 10 > rx.len) continue;
            const atype = (@as(u16, rx_buf[ai]) << 8) | rx_buf[ai+1];
            ai += 2;
            ai += 2; // class
            ai += 4; // TTL
            const rdlen = (@as(u16, rx_buf[ai]) << 8) | rx_buf[ai+1];
            ai += 2;

            if (atype == 1 and rdlen == 4 and ai + 4 <= rx.len) {
                console.write_str("[DNS] resolved");
                return (@as(u32, rx_buf[ai]) << 24) | (@as(u32, rx_buf[ai+1]) << 16) | (@as(u32, rx_buf[ai+2]) << 8) | rx_buf[ai+3];
            }
        }
    }
    return null;
}

fn process_rx() void {
    var rx_pkt: [2048]u8 = undefined;
    const e1000 = @import("../drivers/e1000.zig");
    while (e1000.receive_packet(rx_pkt[0..])) |len| {
        if (len == 0) continue;
        const arp = @import("arp.zig");
        arp.handle_packet(rx_pkt[0..len]);
        udp.handle_packet(rx_pkt[0..len]);
        const dhcp = @import("dhcp.zig");
        dhcp.handle_packet(rx_pkt[0..len]);
    }
}
