const console = @import("drivers/console.zig");
const wd = @import("core/watchdog.zig");
const kmalloc = @import("core/kmalloc.zig");

pub const CrashType = enum(u8) {
    shell = 1 << 0,
    vfs = 1 << 1,
    network = 1 << 2,
};

pub const Module = struct {
    name: []const u8,
    version: u32,
    tick_fn: *const fn () void,
    blocked_types: u8,
};

var l2_stack: [*]volatile u8 = undefined;
var l2_alive: bool = false;
var l2_count: u64 = 0;

var active_module_idx: u32 = 0;
var module_upgrades: u32 = 0;

fn tick_v1() void { l2_count += 1; wd.layer3_beat(); }
fn tick_v2() void { l2_count += 1; wd.layer3_beat(); }
fn tick_v3() void { l2_count += 1; wd.layer3_beat(); }
fn tick_v4() void { l2_count += 1; wd.layer3_beat(); }

pub const MODULES = [_]Module{
    .{ .name = "layer3_v1", .version = 1, .tick_fn = &tick_v1, .blocked_types = 0 },
    .{ .name = "layer3_v2", .version = 2, .tick_fn = &tick_v2, .blocked_types = @intFromEnum(CrashType.shell) },
    .{ .name = "layer3_v3", .version = 3, .tick_fn = &tick_v3, .blocked_types = @intFromEnum(CrashType.shell) | @intFromEnum(CrashType.vfs) },
    .{ .name = "layer3_v4", .version = 4, .tick_fn = &tick_v4, .blocked_types = @intFromEnum(CrashType.shell) | @intFromEnum(CrashType.vfs) | @intFromEnum(CrashType.network) },
};

pub fn get_module() *const Module { return &MODULES[active_module_idx]; }
pub fn get_module_name() []const u8 { return MODULES[active_module_idx].name; }
pub fn get_upgrade_count() u32 { return module_upgrades; }

pub fn init() void {
    const stack = kmalloc.kmalloc(4096) orelse {
        console.write_str("[L3] Failed to allocate stack");
        return;
    };
    l2_stack = @ptrCast(@alignCast(stack));
    l2_alive = true;
    l2_count = 0;
    active_module_idx = 0;
    module_upgrades = 0;
    console.write_str("[L3] Layer 3 started (module: ");
    console.write_str(MODULES[0].name);
    console.write_str(")");
}

pub fn tick() void {
    if (!l2_alive) return;
    MODULES[active_module_idx].tick_fn();
}

pub fn restart() void {
    l2_alive = true;
    l2_count = 0;
    console.write_str("[L3] Layer 3 restarted (module: ");
    console.write_str(MODULES[active_module_idx].name);
    console.write_str(")");
}

pub fn upgrade_module() void {
    if (active_module_idx + 1 >= MODULES.len) {
        console.write_str("[L3] Already at latest module");
        return;
    }
    active_module_idx += 1;
    module_upgrades += 1;
    console.write_str("[L3] Module upgraded to: ");
    console.write_str(MODULES[active_module_idx].name);
}

pub fn force_crash() void {
    crash_with_reason("shell-requested", CrashType.shell);
}

pub fn crash_with_reason(reason: []const u8, ctype: CrashType) void {
    if (!l2_alive) return;
    const blocked = MODULES[active_module_idx].blocked_types;
    if (blocked & @intFromEnum(ctype) != 0) {
        console.write_str("[L3] Module ");
        console.write_str(MODULES[active_module_idx].name);
        console.write_str(" blocks this crash type — ignored");
        return;
    }
    console.write_str("");
    console.write_str("*** LAYER 3 CRASH ***");
    wd.report_crash(reason);
    l2_alive = false;
}
