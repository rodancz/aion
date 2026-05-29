const tcp = @import("tcp.zig");
const console = @import("../drivers/console.zig");

pub fn test_direct(ip: u32, port: u16, api_key: []const u8, out_buf: []u8) ?usize {
    _ = api_key;
    const port_num = 49152 + @import("../arch/x86_64/isr.zig").get_ticks() % 16384;
    const conn = tcp.connect(ip, port, @as(u16, @truncate(port_num))) orelse {
        console.write_str("[DIRECT] connect null");
        return null;
    };
    console.write_str("[DIRECT] SYN sent to host, waiting...");

    // Quick poll for handshake (non-blocking)
    var ticks: u64 = 0;
    while (!tcp.is_established(conn) and ticks < 500) : (ticks += 1) {
        poll();
        poll();
        tcp.tick();
    }
    if (!tcp.is_established(conn)) {
        console.write_str("[DIRECT] handshake in progress (main loop)");
        return null;
    }
    console.write_str("[DIRECT] connected!");

    var req: [512]u8 = undefined;
    var ri: usize = 0;
    const method = "GET / HTTP/1.1\r\nHost: host\r\nConnection: close\r\n\r\n";
    for (method) |c| { req[ri] = c; ri += 1; }
    _ = tcp.send(conn, req[0..ri]);
    tcp.close(conn);

    ticks = 0;
    while (!tcp.is_finished(conn) and ticks < 500) : (ticks += 1) {
        poll();
        poll();
        tcp.tick();
    }

    console.write_str("[DIRECT] done");
    return tcp.recv(conn, out_buf);
}

fn poll() void {
    var rx_pkt: [2048]u8 = undefined;
    const e1000 = @import("../drivers/e1000.zig");
    while (e1000.receive_packet(rx_pkt[0..])) |len| {
        if (len == 0) continue;
        tcp.handle_packet(rx_pkt[0..len]);
    }
}
