const kmalloc = @import("../core/kmalloc.zig");

pub const MsgType = enum(u8) {
    none = 0,
    crash_report = 1,
    rebuild_cmd = 2,
    heartbeat = 3,
    status_query = 4,
};

pub const Message = extern struct {
    msg_type: MsgType align(1),
    source: u8,
    data: [62]u8,
};

const QUEUE_SIZE: usize = 16;

pub const Queue = struct {
    messages: [QUEUE_SIZE]Message,
    head: usize,
    tail: usize,
    count: usize,
};

pub fn queue_create() ?*Queue {
    const mem = kmalloc.kmalloc(@sizeOf(Queue)) orelse return null;
    const q: *Queue = @ptrCast(@alignCast(mem));
    q.head = 0;
    q.tail = 0;
    q.count = 0;
    return q;
}

pub fn queue_send(q: *Queue, msg: Message) bool {
    if (q.count >= QUEUE_SIZE) return false;
    q.messages[q.head] = msg;
    q.head = (q.head + 1) % QUEUE_SIZE;
    q.count += 1;
    return true;
}

pub fn queue_recv(q: *Queue) ?Message {
    if (q.count == 0) return null;
    const msg = q.messages[q.tail];
    q.tail = (q.tail + 1) % QUEUE_SIZE;
    q.count -= 1;
    return msg;
}

pub fn queue_count(q: *const Queue) usize {
    return q.count;
}
