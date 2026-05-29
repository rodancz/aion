const multiboot2 = @import("../multiboot2.zig");

const PAGE_SIZE: usize = 4096;

var bitmap: [*]volatile u8 = undefined;
var bitmap_size_bytes: usize = 0;
var bitmap_total_pages: usize = 0;
var bitmap_free_pages: usize = 0;
var highest_phys_addr: usize = 0;

inline fn align_up(addr: usize, alignment: usize) usize {
    return (addr + alignment - 1) & ~(alignment - 1);
}

inline fn align_down(addr: usize, alignment: usize) usize {
    return addr & ~(alignment - 1);
}

fn bitmap_set(page_idx: usize) void {
    const byte_idx = page_idx >> 3;
    const bit: u3 = @truncate(page_idx & 7);
    const mask = @as(u8, 1) << bit;
    if (bitmap[byte_idx] & mask == 0) {
        bitmap[byte_idx] |= mask;
        bitmap_free_pages -= 1;
    }
}

fn bitmap_clear(page_idx: usize) void {
    const byte_idx = page_idx >> 3;
    const bit: u3 = @truncate(page_idx & 7);
    const mask = @as(u8, 1) << bit;
    if (bitmap[byte_idx] & mask != 0) {
        bitmap[byte_idx] &= ~mask;
        bitmap_free_pages += 1;
    }
}

fn mark_range(start_addr: usize, end_addr: usize, used: bool) void {
    const start_page = align_down(start_addr, PAGE_SIZE) / PAGE_SIZE;
    const end_page = align_up(end_addr, PAGE_SIZE) / PAGE_SIZE;
    var page = start_page;
    while (page < end_page) : (page += 1) {
        if (used) {
            bitmap_set(page);
        } else {
            bitmap_clear(page);
        }
    }
}

pub fn init(mbi_addr: u32, kernel_start: usize, kernel_end: usize) void {
    var iter = multiboot2.parse(mbi_addr) orelse return;

    var max_addr: usize = 0;

    while (iter.next()) |tag| {
        switch (tag.tag_type) {
            4 => {
                const meminfo: *const extern struct { tag_type: u32, size: u32, mem_lower: u32, mem_upper: u32 } = @ptrCast(@alignCast(tag));
                const upper_addr = @as(usize, meminfo.mem_upper) * 1024 + 0x100000;
                if (upper_addr > max_addr) max_addr = upper_addr;
            },
            6 => {
                const mmap: *const multiboot2.MmapTag = @ptrCast(@alignCast(tag));
                const entry_count = (mmap.size - 16) / mmap.entry_size;
                const entries: [*]const multiboot2.MemoryMapEntry = @ptrFromInt(@intFromPtr(tag) + 16);
                var i: usize = 0;
                while (i < entry_count) : (i += 1) {
                    const ent = entries[i];
                    if (ent.mem_type == @intFromEnum(multiboot2.MemoryType.available)) {
                        const ent_end = ent.base_addr + ent.length;
                        if (ent_end > max_addr) max_addr = @truncate(ent_end);
                    }
                }
            },
            else => {},
        }
    }

    if (max_addr == 0) return;

    highest_phys_addr = max_addr;
    bitmap_total_pages = align_up(max_addr, PAGE_SIZE) / PAGE_SIZE;
    bitmap_size_bytes = align_up(bitmap_total_pages / 8, PAGE_SIZE);

    const bitmap_phys_start = align_up(kernel_end, PAGE_SIZE);
    const bitmap_phys_end = bitmap_phys_start + bitmap_size_bytes;

    bitmap = @ptrFromInt(bitmap_phys_start);

    var p: usize = 0;
    while (p < bitmap_size_bytes) : (p += 1) {
        bitmap[p] = 0xFF;
    }
    bitmap_free_pages = 0;

    iter = multiboot2.parse(mbi_addr) orelse return;

    while (iter.next()) |tag| {
        if (tag.tag_type == 6) {
            const mmap: *const multiboot2.MmapTag = @ptrCast(@alignCast(tag));
            const entry_count = (mmap.size - 16) / mmap.entry_size;
            const entries: [*]const multiboot2.MemoryMapEntry = @ptrFromInt(@intFromPtr(tag) + 16);
            var i: usize = 0;
            while (i < entry_count) : (i += 1) {
                const ent = entries[i];
                if (ent.mem_type == @intFromEnum(multiboot2.MemoryType.available)) {
                    mark_range(@truncate(ent.base_addr), @truncate(ent.base_addr + ent.length), false);
                }
            }
        } else if (tag.tag_type == 4) {
            const meminfo: *const extern struct { tag_type: u32, size: u32, mem_lower: u32, mem_upper: u32 } = @ptrCast(@alignCast(tag));
            mark_range(0x100000, @as(usize, meminfo.mem_upper) * 1024 + 0x100000, false);
        }
    }

    mark_range(kernel_start, kernel_end, true);
    mark_range(bitmap_phys_start, bitmap_phys_end, true);
    mark_range(0, 0x100000, true);
}

pub fn alloc_frame() ?usize {
    var byte_idx: usize = 0;
    while (byte_idx < bitmap_size_bytes) : (byte_idx += 1) {
        const b = bitmap[byte_idx];
        if (b != 0xFF) {
            var bit: u3 = 0;
            while (bit < 8) : (bit += 1) {
                if ((b & (@as(u8, 1) << bit)) == 0) {
                    const page_idx = (byte_idx << 3) | bit;
                    bitmap_set(page_idx);
                    return page_idx * PAGE_SIZE;
                }
            }
        }
    }
    return null;
}

pub fn free_frame(addr: usize) void {
    const page_idx = align_down(addr, PAGE_SIZE) / PAGE_SIZE;
    bitmap_clear(page_idx);
}

pub fn total_memory() u64 {
    return @truncate(highest_phys_addr);
}

pub fn free_memory() u64 {
    return @as(u64, bitmap_free_pages) * PAGE_SIZE;
}
