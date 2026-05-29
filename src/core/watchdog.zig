const console = @import("../drivers/console.zig");
const ipc = @import("../ipc/queue.zig");

var heartbeat_count: u64 = 0;
var ticks_since_heartbeat: u64 = 0;
var crash_count: u64 = 0;
var layer3_crashed: bool = false;
var crash_ticks: u64 = 0;
var armed: bool = false;
var l2_zone_start: usize = 0;
var l2_zone_end: usize = 0;
var ai_inbox: ?*ipc.Queue = null;

pub fn set_ai_queue(q: *ipc.Queue) void {
    ai_inbox = q;
}

pub fn tick() void {
    if (!armed) return;
    ticks_since_heartbeat += 1;

    if (layer3_crashed) {
        crash_ticks += 1;
        return;
    }

    if (ticks_since_heartbeat > 200) {
        console.write_str("WATCHDOG: heartbeat timeout - Layer 3 dead");
        layer3_crashed = true;
        crash_ticks = 0;
    }
}

pub fn arm() void {
    armed = true;
    ticks_since_heartbeat = 0;
}

pub fn set_zone(start: usize, end: usize) void {
    l2_zone_start = start;
    l2_zone_end = end;
}

pub fn is_in_zone(addr: usize) bool {
    if (l2_zone_start == 0 and l2_zone_end == 0) return false;
    return addr >= l2_zone_start and addr < l2_zone_end;
}

pub fn layer3_beat() void {
    heartbeat_count += 1;
    ticks_since_heartbeat = 0;
}

pub fn reset_ticks() void {
    ticks_since_heartbeat = 0;
}

pub fn report_crash(reason: []const u8) void {
    layer3_crashed = true;
    crash_ticks = 0;
    crash_count += 1;

    if (ai_inbox) |q| {
        var msg: ipc.Message = undefined;
        msg.msg_type = ipc.MsgType.crash_report;
        msg.source = 0;
        msg.data = [_]u8{0} ** 62;
        const copy_len = if (reason.len < 62) reason.len else 62;
        for (reason[0..copy_len], 0..) |c, j| {
            msg.data[j] = c;
        }
        _ = ipc.queue_send(q, msg);
    }
}

pub fn is_healthy() bool {
    return !layer3_crashed;
}

pub fn reset() void {
    layer3_crashed = false;
    ticks_since_heartbeat = 0;
    crash_ticks = 0;
}

pub fn get_crash_count() u64 {
    return crash_count;
}
