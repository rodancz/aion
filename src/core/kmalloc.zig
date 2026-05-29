const pmm = @import("../core/pmm.zig");

const PAGE_SIZE: usize = 4096;

const BLOCK_SIZES = [_]usize{ 16, 32, 64, 128, 256, 512, 1024, 2048 };

const SlabHeader = struct {
    next: ?*SlabHeader,
    free_count: usize,
    block_size: usize,
    total_blocks: usize,
    first_free: usize,
};

var slab_heads: [BLOCK_SIZES.len]?*SlabHeader = [_]?*SlabHeader{null} ** BLOCK_SIZES.len;

fn size_class(size: usize) ?usize {
    for (BLOCK_SIZES, 0..) |s, i| {
        if (size <= s) return i;
    }
    return null;
}

fn read_free_ptr(addr: usize) usize {
    const p: *align(1) const usize = @ptrFromInt(addr);
    return p.*;
}

fn write_free_ptr(addr: usize, val: usize) void {
    const p: *align(1) usize = @ptrFromInt(addr);
    p.* = val;
}

fn create_slab(class: usize) ?*SlabHeader {
    const page = pmm.alloc_frame() orelse return null;
    const slab: *SlabHeader = @ptrFromInt(page);
    const block_size = BLOCK_SIZES[class];

    const header_bytes = (@sizeOf(SlabHeader) + block_size - 1) / block_size * block_size;
    const body_start = page + header_bytes;
    const body_size = PAGE_SIZE - header_bytes;
    const block_count = body_size / block_size;

    slab.next = null;
    slab.free_count = 0;
    slab.block_size = block_size;
    slab.total_blocks = block_count;
    slab.first_free = body_start;

    var i: usize = 0;
    while (i < block_count) : (i += 1) {
        const block_addr = body_start + i * block_size;
        if (i < block_count - 1) {
            write_free_ptr(block_addr, block_addr + block_size);
        } else {
            write_free_ptr(block_addr, 0);
        }
        slab.free_count += 1;
    }

    return slab;
}

pub fn kmalloc(size: usize) ?*anyopaque {
    if (size == 0) return null;

    const class = size_class(size) orelse {
        return @ptrFromInt(pmm.alloc_frame() orelse return null);
    };

    var slab = slab_heads[class];
    while (slab) |s| {
        if (s.free_count > 0) break;
        slab = s.next;
    }

    if (slab == null) {
        slab = create_slab(class) orelse return null;
        slab.?.next = slab_heads[class];
        slab_heads[class] = slab;
    }

    const s = slab.?;
    const block_addr = s.first_free;
    s.first_free = read_free_ptr(block_addr);
    s.free_count -= 1;

    return @ptrFromInt(block_addr);
}

fn slab_of(ptr: *anyopaque) *SlabHeader {
    const addr = @intFromPtr(ptr);
    return @ptrFromInt(addr & ~(PAGE_SIZE - 1));
}

pub fn kfree(ptr: *anyopaque) void {
    const addr = @intFromPtr(ptr);
    if (addr & (PAGE_SIZE - 1) == 0) {
        pmm.free_frame(addr);
        return;
    }

    const slab = slab_of(ptr);
    write_free_ptr(addr, slab.first_free);
    slab.first_free = addr;
    slab.free_count += 1;
}

pub fn kmalloc_z(size: usize) ?*anyopaque {
    const ptr = kmalloc(size) orelse return null;
    const bytes: [*]u8 = @ptrCast(ptr);
    var i: usize = 0;
    while (i < size) : (i += 1) {
        bytes[i] = 0;
    }
    return ptr;
}
