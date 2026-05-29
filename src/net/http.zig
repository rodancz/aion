const tcp = @import("tcp.zig");
const dns = @import("dns.zig");
const tls = @import("tls.zig");
const console = @import("../drivers/console.zig");

pub fn post_json(hostname: []const u8, port: u16, path: []const u8, body: []const u8, out_buf: []u8) ?usize {
    if (port == 443) return post_json_tls(hostname, port, path, body, out_buf);

    const ip = dns.resolve(hostname) orelse {
        console.write_str("[HTTP] DNS failed");
        return null;
    };

    const conn = tcp.connect(ip, port, @truncate(49152 + (@import("../arch/x86_64/isr.zig").get_ticks() % 16384))) orelse {
        console.write_str("[HTTP] TCP failed");
        return null;
    };

    var ticks: u64 = 0;
    while (!tcp.is_established(conn) and ticks < 500) : (ticks += 1) {
        process_net();
        tcp.tick();
        spin(100000);
    }
    if (!tcp.is_established(conn)) return null;

    return send_http(conn, hostname, path, body, out_buf, false);
}

fn post_json_tls(hostname: []const u8, port: u16, path: []const u8, body: []const u8, out_buf: []u8) ?usize {
    _ = port;
    const conn = tls.tls_connect(hostname, 443) orelse {
        console.write_str("[HTTPS] TLS failed");
        return null;
    };
    return send_http(conn, hostname, path, body, out_buf, true);
}

fn send_http(conn: *tcp.TcpConn, hostname: []const u8, path: []const u8, body: []const u8, out_buf: []u8, use_tls: bool) ?usize {
    if (use_tls) {
        _ = tls.tls_send(conn, build_request(hostname, path, body));
    } else {
        _ = tcp.send(conn, build_request(hostname, path, body));
    }
    tcp.close(conn);

    var ticks: u64 = 0;
    while (!tcp.is_finished(conn) and ticks < 2000) : (ticks += 1) {
        process_net();
        tcp.tick();
        spin(50000);
    }

    if (use_tls) return tls.tls_recv(conn, out_buf);
    return tcp.recv(conn, out_buf);
}

var http_req_buf: [2048]u8 = undefined;

fn build_request(hostname: []const u8, path: []const u8, body: []const u8) []u8 {
    var ri: usize = 0;

    const method = if (body.len > 0) "POST " else "GET ";
    for (method) |c| { http_req_buf[ri] = c; ri += 1; }
    for (path) |c| { http_req_buf[ri] = c; ri += 1; }
    for (" HTTP/1.1\r\nHost: ") |c| { http_req_buf[ri] = c; ri += 1; }
    for (hostname) |c| { http_req_buf[ri] = c; ri += 1; }

    if (body.len > 0) {
        for ("\r\nContent-Type: application/json\r\nContent-Length: ") |c| { http_req_buf[ri] = c; ri += 1; }
        ri += write_u64(&http_req_buf, ri, body.len);
    }

    for ("\r\nConnection: close\r\n\r\n") |c| { http_req_buf[ri] = c; ri += 1; }
    for (body) |c| { http_req_buf[ri] = c; ri += 1; }

    return http_req_buf[0..ri];
}

pub fn get_json(hostname: []const u8, port: u16, path: []const u8, out_buf: []u8) ?usize {
    const empty: []const u8 = &[_]u8{};
    return post_json(hostname, port, path, empty, out_buf);
}

pub fn parse_body(response: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 3 < response.len) : (i += 1) {
        if (response[i] == '\r' and response[i+1] == '\n' and response[i+2] == '\r' and response[i+3] == '\n') {
            return response[i+4..];
        }
    }
    return null;
}

fn write_u64(buf: []u8, start: usize, val: usize) usize {
    if (val == 0) {
        buf[start] = '0';
        return 1;
    }
    var tmp: [20]u8 = undefined;
    var ti: usize = 0;
    var v = val;
    while (v > 0) : (v /= 10) {
        tmp[ti] = @as(u8, @truncate(v % 10)) + '0';
        ti += 1;
    }
    var oi = start;
    while (ti > 0) : (ti -= 1) {
        buf[oi] = tmp[ti - 1];
        oi += 1;
    }
    return oi - start;
}

fn process_net() void {
    var rx_pkt: [2048]u8 = undefined;
    const e1000 = @import("../drivers/e1000.zig");
    if (e1000.receive_packet(rx_pkt[0..])) |len| {
        if (len == 0) return;
        const arp = @import("arp.zig");
        arp.handle_packet(rx_pkt[0..len]);
        tcp.handle_packet(rx_pkt[0..len]);
        const udp = @import("udp.zig");
        udp.handle_packet(rx_pkt[0..len]);
        const dhcp = @import("dhcp.zig");
        dhcp.handle_packet(rx_pkt[0..len]);
    }
}

fn spin(n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {}
}
