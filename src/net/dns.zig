const udp = @import("udp.zig");
const console = @import("../drivers/console.zig");

pub fn resolve(hostname: []const u8) ?u32 {
    if (udp.dns_ip == 0) return null;

    // Build DNS query
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
        const label_start = hi;
        while (hi < hostname.len and hostname[hi] != '.') : (hi += 1) {}
        const label_len = hi - label_start;
        query[qi] = @truncate(label_len);
        qi += 1;
        var j: usize = 0;
        while (j < label_len) : (j += 1) {
            query[qi] = hostname[label_start + j];
            qi += 1;
        }
        if (hi < hostname.len and hostname[hi] == '.') hi += 1;
    }
    query[qi] = 0; qi += 1;
    query[qi] = 0; qi += 1; query[qi] = 1; qi += 1; // QTYPE=A
    query[qi] = 0; qi += 1; query[qi] = 1; qi += 1; // QCLASS=IN

    // Flush stale UDP
    var flush_buf: [2048]u8 = undefined;
    process_rx();
    _ = udp.receive(flush_buf[0..]);
    process_rx();
    _ = udp.receive(flush_buf[0..]);

    // Send query
    if (!udp.send_udp(udp.dns_ip, 1025, 53, query[0..qi])) {
        console.write_str("[DNS] send fail");
        return null;
    }
    console.write_str("[DNS] sent");

    // Poll for response
    var ticks: u64 = 0;
    var rx_buf: [2048]u8 = undefined;
    while (ticks < 100) : (ticks += 1) {
        process_rx();
        if (udp.receive(rx_buf[0..])) |rx| {
            if (rx.dst_port == 1025 and rx.src_port == 53) {
                const rtxid = (@as(u16, rx_buf[0]) << 8) | rx_buf[1];
                if (rtxid != txid) continue;
                const flags = (@as(u16, rx_buf[2]) << 8) | rx_buf[3];
                if ((flags & 0x8000) == 0) continue;
                const ancount = (@as(u16, rx_buf[6]) << 8) | rx_buf[7];
                if (ancount == 0) return null;

                var ai: usize = 12;
                if ((rx_buf[ai] & 0xC0) == 0xC0) {
                    ai += 2;
                } else {
                    while (ai < rx.len and rx_buf[ai] != 0) : (ai += 1) {}
                    ai += 1;
                }
                ai += 4; // skip QTYPE+QCLASS
                if (ai + 10 > rx.len) return null;

                const atype = (@as(u16, rx_buf[ai]) << 8) | rx_buf[ai+1];
                ai += 2; // TYPE
                ai += 2; // CLASS
                ai += 4; // TTL
                const rdlength = (@as(u16, rx_buf[ai]) << 8) | rx_buf[ai+1];
                ai += 2;

                if (atype == 1 and rdlength == 4 and ai + 4 <= rx.len) {
                    return (@as(u32, rx_buf[ai]) << 24) | (@as(u32, rx_buf[ai+1]) << 16) | (@as(u32, rx_buf[ai+2]) << 8) | rx_buf[ai+3];
                }
                return null;
            }
        }
    }

    return null;
}

fn process_rx() void {
    var rx_pkt: [2048]u8 = undefined;
    const e1000 = @import("../drivers/e1000.zig");
    if (e1000.receive_packet(rx_pkt[0..])) |len| {
        if (len == 0) return;
        const arp = @import("arp.zig");
        arp.handle_packet(rx_pkt[0..len]);
        udp.handle_packet(rx_pkt[0..len]);
        const dhcp = @import("dhcp.zig");
        dhcp.handle_packet(rx_pkt[0..len]);
    }
}
