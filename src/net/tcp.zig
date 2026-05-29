const e1000 = @import("../drivers/e1000.zig");
const arp = @import("arp.zig");
const udp = @import("udp.zig");
const console = @import("../drivers/console.zig");

const MAX_CONNS = 4;
const MSS: usize = 1460;
const WIN_SIZE: u16 = 8192;
const RETX_TIMEOUT: u64 = 100; // ticks
const MAX_RETX: u8 = 5;

pub const TcpState = enum(u8) {
    closed,
    syn_sent,
    established,
    fin_wait1,
    fin_wait2,
    time_wait,
};

pub const TcpConn = struct {
    state: TcpState,
    local_port: u16,
    remote_ip: u32,
    remote_port: u16,
    snd_una: u32, // oldest unacknowledged sequence number
    snd_nxt: u32, // next sequence number to send
    snd_wnd: u16, // receiver's window
    rcv_nxt: u32, // next expected receive sequence number
    iss: u32,     // initial send sequence number
    retx_timer: u64,
    retx_count: u8,
    retx_seq: u32,
    retx_len: usize,
    retx_data: [MSS]u8,
    rx_buf: [8192]u8,
    rx_len: usize,
    rx_finished: bool,
    checksum_scratch: [2048]u8,
};

var conns: [MAX_CONNS]TcpConn = undefined;
var conn_count: usize = 0;

pub fn init() void {
    conn_count = 0;
}

pub fn connect(remote_ip: u32, remote_port: u16, local_port: u16) ?*TcpConn {
    if (conn_count >= MAX_CONNS) return null;

    const ticks = @import("../arch/x86_64/isr.zig").get_ticks();
    const conn = &conns[conn_count];
    conn.state = .syn_sent;
    conn.local_port = local_port;
    conn.remote_ip = remote_ip;
    conn.remote_port = remote_port;
    conn.iss = @truncate(ticks);
    conn.snd_una = conn.iss;
    conn.snd_nxt = conn.iss + 1;
    conn.rcv_nxt = 0;
    conn.rx_len = 0;
    conn.rx_finished = false;
    conn.retx_count = 0;
    conn.retx_timer = 0;
    conn_count += 1;

    send_syn(conn);
    return conn;
}

pub fn close(conn: *TcpConn) void {
    if (conn.state == .established) {
        conn.state = .fin_wait1;
        conn.snd_nxt += 1;
        send_segment(conn, 0x11, null, 0, 0); // FIN+ACK
    } else {
        conn.state = .closed;
    }
}

pub fn send(conn: *TcpConn, data: []const u8) bool {
    if (conn.state != .established) return false;
    send_segment(conn, 0x18, data, 0, data.len); // PSH+ACK
    return true;
}

pub fn recv(conn: *TcpConn, buf: []u8) ?usize {
    if (conn.rx_finished and conn.rx_len > 0) {
        const len = if (conn.rx_len > buf.len) buf.len else conn.rx_len;
        var i: usize = 0;
        while (i < len) : (i += 1) buf[i] = conn.rx_buf[i];
        // Shift remaining data
        const remaining = conn.rx_len - len;
        if (remaining > 0) {
            var j: usize = 0;
            while (j < remaining) : (j += 1) conn.rx_buf[j] = conn.rx_buf[len + j];
        }
        conn.rx_len = remaining;
        if (remaining == 0) conn.rx_finished = false;
        return len;
    }
    if (conn.state == .closed or conn.state == .time_wait) {
        if (conn.rx_len > 0) {
            const len = if (conn.rx_len > buf.len) buf.len else conn.rx_len;
            var i: usize = 0;
            while (i < len) : (i += 1) buf[i] = conn.rx_buf[i];
            conn.rx_len = 0;
            return len;
        }
    }
    return null;
}

pub fn is_established(conn: *TcpConn) bool {
    return conn.state == .established;
}

pub fn is_finished(conn: *TcpConn) bool {
    return conn.state == .closed or conn.state == .time_wait;
}

pub fn tick() void {
    const ticks = @import("../arch/x86_64/isr.zig").get_ticks();
    var i: usize = 0;
    while (i < conn_count) : (i += 1) {
        const conn = &conns[i];
        if (conn.state == .syn_sent and conn.retx_count > 0 and ticks - conn.retx_timer >= RETX_TIMEOUT) {
            if (conn.retx_count < MAX_RETX) {
                conn.retx_timer = ticks;
                conn.retx_count += 1;
                send_syn(conn);
            } else {
                conn.state = .closed;
            }
        }
        if (conn.state != .closed and conn.retx_count > 0 and ticks - conn.retx_timer >= RETX_TIMEOUT and conn.retx_seq != 0) {
            if (conn.retx_count < MAX_RETX) {
                conn.retx_timer = ticks;
                conn.retx_count += 1;
                send_segment(conn, 0x18, conn.retx_data[0..conn.retx_len], conn.retx_seq - conn.iss, conn.retx_len);
            } else {
                conn.state = .closed;
            }
        }
    }
}

fn send_syn(conn: *TcpConn) void {
    const ticks = @import("../arch/x86_64/isr.zig").get_ticks();
    conn.retx_timer = ticks;
    conn.retx_count = 1;
    send_segment(conn, 0x02, null, 0, 0); // SYN
}

fn send_segment(conn: *TcpConn, flags: u8, data: ?[]const u8, seq_off: u32, data_len: usize) void {
    const data_slice = data orelse (&[_]u8{});
    const tcp_hdr_len: usize = 20;
    const pkt_len = tcp_hdr_len + data_len;

    if (pkt_len > conn.checksum_scratch.len) return;
    const pkt = conn.checksum_scratch[0..pkt_len];
    var j: usize = 0;
    while (j < pkt_len) : (j += 1) pkt[j] = 0;

    const seq = conn.iss + seq_off;

    pkt[0] = @truncate(conn.local_port >> 8);
    pkt[1] = @truncate(conn.local_port);
    pkt[2] = @truncate(conn.remote_port >> 8);
    pkt[3] = @truncate(conn.remote_port);
    pkt[4] = @truncate(seq >> 24);
    pkt[5] = @truncate(seq >> 16);
    pkt[6] = @truncate(seq >> 8);
    pkt[7] = @truncate(seq);
    pkt[8] = @truncate(conn.rcv_nxt >> 24);
    pkt[9] = @truncate(conn.rcv_nxt >> 16);
    pkt[10] = @truncate(conn.rcv_nxt >> 8);
    pkt[11] = @truncate(conn.rcv_nxt);
    pkt[12] = 0x50; // data offset = 5 (20 bytes)
    pkt[13] = flags;
    pkt[14] = @truncate(WIN_SIZE >> 8);
    pkt[15] = @truncate(WIN_SIZE);
    // checksum at 16-17, zero for now
    pkt[18] = 0; pkt[19] = 0; // urgent pointer

    // Copy data
    if (data_len > 0) {
        var k: usize = 0;
        while (k < data_len) : (k += 1) {
            pkt[20 + k] = data_slice[k];
        }
    }

    // Compute TCP checksum
    const tcp_cksum = compute_tcp_checksum(conn, pkt[0..pkt_len], pkt_len);
    pkt[16] = @truncate(tcp_cksum >> 8);
    pkt[17] = @truncate(tcp_cksum);

    // Build IP packet
    const total_len: u16 = @truncate(20 + pkt_len);
    var ip_buf: [2048]u8 = [_]u8{0} ** 2048;

    const mac_slice = e1000.get_mac();
    ip_buf[0] = arp.gateway_mac[0]; ip_buf[1] = arp.gateway_mac[1];
    ip_buf[2] = arp.gateway_mac[2]; ip_buf[3] = arp.gateway_mac[3];
    ip_buf[4] = arp.gateway_mac[4]; ip_buf[5] = arp.gateway_mac[5];
    ip_buf[6] = mac_slice[0]; ip_buf[7] = mac_slice[1];
    ip_buf[8] = mac_slice[2]; ip_buf[9] = mac_slice[3];
    ip_buf[10] = mac_slice[4]; ip_buf[11] = mac_slice[5];
    ip_buf[12] = 0x08; ip_buf[13] = 0x00;

    ip_buf[14] = 0x45; ip_buf[15] = 0;
    ip_buf[16] = @truncate(total_len >> 8);
    ip_buf[17] = @truncate(total_len & 0xFF);
    ip_buf[18] = 0; ip_buf[19] = 0;
    ip_buf[20] = 0; ip_buf[21] = 0;
    ip_buf[22] = 64;
    ip_buf[23] = 6; // TCP

    ip_buf[24] = 0; ip_buf[25] = 0; // checksum placeholder

    // Src IP (network byte order)
    ip_buf[26] = @truncate((udp.my_ip >> 24) & 0xFF);
    ip_buf[27] = @truncate((udp.my_ip >> 16) & 0xFF);
    ip_buf[28] = @truncate((udp.my_ip >> 8) & 0xFF);
    ip_buf[29] = @truncate(udp.my_ip & 0xFF);

    // Dst IP (network byte order)
    ip_buf[30] = @truncate((conn.remote_ip >> 24) & 0xFF);
    ip_buf[31] = @truncate((conn.remote_ip >> 16) & 0xFF);
    ip_buf[32] = @truncate((conn.remote_ip >> 8) & 0xFF);
    ip_buf[33] = @truncate(conn.remote_ip & 0xFF);

    // IP checksum
    var ip_sum: u32 = 0;
    var k: usize = 14;
    while (k < 34) : (k += 2) {
        const word: u16 = (@as(u16, ip_buf[k]) << 8) | ip_buf[k + 1];
        ip_sum += word;
    }
    while (ip_sum > 0xFFFF) {
        ip_sum = (ip_sum & 0xFFFF) + (ip_sum >> 16);
    }
    const ip_cksum: u16 = @truncate(~ip_sum & 0xFFFF);
    ip_buf[24] = @truncate(ip_cksum >> 8);
    ip_buf[25] = @truncate(ip_cksum & 0xFF);

    // Copy TCP segment after IP header
    k = 0;
    while (k < pkt_len) : (k += 1) {
        ip_buf[34 + k] = pkt[k];
    }

    // Store for retransmission
    if (flags & 0x18 != 0 and data_len > 0) {
        conn.retx_seq = seq;
        conn.retx_len = data_len;
        var m: usize = 0;
        while (m < data_len and m < MSS) : (m += 1) {
            conn.retx_data[m] = data_slice[m];
        }
    } else if (flags & 0x02 != 0) {
        conn.retx_seq = 0;
        conn.retx_len = 0;
    }

    _ = e1000.send_packet(ip_buf[0 .. 34 + pkt_len]);
}

fn compute_tcp_checksum(conn: *TcpConn, segment: []const u8, seg_len: usize) u16 {
    // Pseudo-header
    var sum: u32 = 0;

    // Source IP
    sum += (udp.my_ip >> 16) & 0xFFFF;
    sum += udp.my_ip & 0xFFFF;

    // Dest IP
    sum += (conn.remote_ip >> 16) & 0xFFFF;
    sum += conn.remote_ip & 0xFFFF;

    // Protocol (6) + TCP length
    sum += @as(u32, 6);
    sum += @as(u32, @intCast(seg_len));

    // TCP segment
    var i: usize = 0;
    while (i < seg_len - 1) : (i += 2) {
        sum += (@as(u16, segment[i]) << 8) | segment[i + 1];
    }
    if (seg_len & 1 != 0) {
        sum += @as(u16, segment[seg_len - 1]) << 8;
    }

    while (sum > 0xFFFF) {
        sum = (sum & 0xFFFF) + (sum >> 16);
    }
    return @as(u16, @truncate(~sum));
}

// Find matching TCP connection for incoming packet
fn find_conn(remote_ip: u32, remote_port: u16, local_port: u16) ?*TcpConn {
    var i: usize = 0;
    while (i < conn_count) : (i += 1) {
        const conn = &conns[i];
        if (conn.state == .closed or conn.state == .time_wait) continue;
        if (conn.remote_ip == remote_ip and conn.remote_port == remote_port) {
            conn.local_port = local_port;
            return conn;
        }
    }
    return null;
}

pub fn handle_packet(pkt: []const u8) void {
    if (pkt.len < 54) return;
    if (pkt[12] != 0x08 or pkt[13] != 0x00) return;
    if (pkt[23] != 6) return;

    const src_ip = (@as(u32, pkt[26]) << 24) | (@as(u32, pkt[27]) << 16) | (@as(u32, pkt[28]) << 8) | pkt[29];
    _ = (@as(u32, pkt[30]) << 24) | (@as(u32, pkt[31]) << 16) | (@as(u32, pkt[32]) << 8) | pkt[33];

    const tcp_start: usize = 34;
    const src_port = (@as(u16, pkt[tcp_start]) << 8) | pkt[tcp_start + 1];
    const dst_port = (@as(u16, pkt[tcp_start + 2]) << 8) | pkt[tcp_start + 3];

    const conn = find_conn(src_ip, src_port, dst_port) orelse return;

    const seq = (@as(u32, pkt[tcp_start + 4]) << 24) | (@as(u32, pkt[tcp_start + 5]) << 16) | (@as(u32, pkt[tcp_start + 6]) << 8) | pkt[tcp_start + 7];
    const ack = (@as(u32, pkt[tcp_start + 8]) << 24) | (@as(u32, pkt[tcp_start + 9]) << 16) | (@as(u32, pkt[tcp_start + 10]) << 8) | pkt[tcp_start + 11];
    const data_offset: usize = @as(usize, (pkt[tcp_start + 12] >> 4) * 4);
    const flags = pkt[tcp_start + 13];

    if (data_offset < 20) return;

    const payload_start = tcp_start + data_offset;
    const payload_len = if (pkt.len > payload_start) pkt.len - payload_start else 0;

    // Check sequence number
    var acceptable: bool = false;
    if (conn.state == .syn_sent) {
        acceptable = true; // SYN-ACK has special seq handling
    } else {
        const seg_end = seq +% @as(u32, @truncate(payload_len));
        if (payload_len > 0) {
            // Must overlap receive window
            if (seq < conn.rcv_nxt + WIN_SIZE and seg_end > conn.rcv_nxt) {
                acceptable = true;
            }
        } else if (seq == conn.rcv_nxt or (seq >= conn.rcv_nxt and seq < conn.rcv_nxt + WIN_SIZE)) {
            acceptable = true;
        }
    }

    if (!acceptable and !(flags & 0x10 != 0)) return; // ignore non-ACK packets out of window

    switch (conn.state) {
        .syn_sent => {
            if (flags & 0x12 == 0x12) { // SYN+ACK
                if (ack == conn.snd_nxt) {
                    conn.rcv_nxt = seq +% 1;
                    conn.snd_una = ack;
                    conn.retx_count = 0;
                    conn.retx_seq = 0;
                    conn.state = .established;
                    console.write_str("[TCP] Handshake complete");
                    send_segment(conn, 0x10, null, 0, 0);
                }
            } else if (flags & 0x04 != 0) { // RST
                conn.state = .closed;
            }
        },
        .established => {
            // Process ACK
            if (flags & 0x10 != 0) {
                if (ack > conn.snd_una) {
                    conn.snd_una = ack;
                    conn.retx_count = 0;
                    conn.retx_seq = 0;
                    conn.retx_len = 0;
                }
            }

            // Process data
            if (payload_len > 0 and seq == conn.rcv_nxt) {
                const space = conn.rx_buf.len - conn.rx_len;
                const copy_len = if (payload_len < space) payload_len else space;
                var m: usize = 0;
                while (m < copy_len) : (m += 1) {
                    conn.rx_buf[conn.rx_len + m] = pkt[payload_start + m];
                }
                conn.rx_len += copy_len;
                conn.rcv_nxt = seq +% @as(u32, @truncate(copy_len));
                // Send ACK for received data
                send_segment(conn, 0x10, null, 0, 0);
            } else if (payload_len > 0 and seq != conn.rcv_nxt) {
                // Out of order - send ACK for last in-order byte
                send_segment(conn, 0x10, null, 0, 0);
            }

            // Check FIN
            if (flags & 0x01 != 0) {
                conn.rcv_nxt = seq +% @as(u32, @truncate(payload_len)) +% 1;
                conn.rx_finished = true;
                send_segment(conn, 0x10, null, 0, 0); // ACK the FIN
                // Don't close yet - let caller read remaining data
            }
        },
        .fin_wait1 => {
            if (flags & 0x10 != 0) {
                if (ack == conn.snd_nxt) {
                    conn.snd_una = ack;
                    if (flags & 0x01 != 0) {
                        // FIN+ACK - both sides done
                        send_segment(conn, 0x10, null, 0, 0);
                        conn.state = .time_wait;
                    } else {
                        conn.state = .fin_wait2;
                    }
                }
            }
        },
        .fin_wait2 => {
            if (flags & 0x01 != 0) {
                conn.rcv_nxt = seq +% 1;
                conn.rx_finished = true;
                send_segment(conn, 0x10, null, 0, 0);
                conn.state = .time_wait;
            }
        },
        else => {},
    }
}
