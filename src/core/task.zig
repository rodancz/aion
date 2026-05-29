const pmm = @import("pmm.zig");
const kmalloc = @import("kmalloc.zig");

const TASK_STACK_PAGES: usize = 4;

pub const Task = struct {
    name: []const u8,
    entry: *const fn () callconv(.c) void,
    code_start: usize,
    code_end: usize,
    heartbeat: u64,
    last_heartbeat: u64,
    healthy: bool,
    restart_count: u64,
    stack_ptr: usize,
    stack_phys: usize,
};

pub fn create(name: []const u8, entry: *const fn () callconv(.c) void, code_start: usize, code_end: usize) ?*Task {
    const task = kmalloc.kmalloc(@sizeOf(Task)) orelse return null;
    const t: *Task = @ptrCast(@alignCast(task));

    const stack = pmm.alloc_frame() orelse {
        kmalloc.kfree(task);
        return null;
    };

    t.name = name;
    t.entry = entry;
    t.code_start = code_start;
    t.code_end = code_end;
    t.heartbeat = 0;
    t.last_heartbeat = 0;
    t.healthy = true;
    t.restart_count = 0;
    t.stack_ptr = stack + TASK_STACK_PAGES * 4096;
    t.stack_phys = stack;

    return t;
}
