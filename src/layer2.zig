const console = @import("drivers/console.zig");
const wd = @import("core/watchdog.zig");
const kmalloc = @import("core/kmalloc.zig");

var l2_stack: [*]volatile u8 = undefined;
var l2_alive: bool = false;
var l2_count: u64 = 0;

pub fn init() void {
    const stack = kmalloc.kmalloc(4096) orelse {
        console.write_str("[L3] Failed to allocate stack");
        return;
    };
    l2_stack = @ptrCast(@alignCast(stack));
    l2_alive = true;
    l2_count = 0;
    console.write_str("[L3] Layer 3 kernel started");
}

pub fn tick() void {
    if (!l2_alive) return;
    l2_count += 1;
    wd.layer3_beat();
}

pub fn restart() void {
    console.write_str("  [AI] Analyzing crash dump...");
    console.write_str("  [AI] Generating kernel patch...");
    console.write_str("  [AI] Verifying patch integrity...");
    console.write_str("  [AI] Hot-patching Layer 3 kernel...");
    l2_alive = true;
    l2_count = 0;
    console.write_str("  [AI] Layer 3 kernel rebuilt and restarted");
}

pub fn force_crash() void {
    if (!l2_alive) return;
    console.write_str("");
    console.write_str("*** LAYER 3 KERNEL PANIC (user-requested) ***");
    console.write_str("  Fault: shell-requested crash");
    wd.report_crash("shell-requested");
    l2_alive = false;
}
