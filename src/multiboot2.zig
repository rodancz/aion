const MbiHeader = extern struct {
    total_size: u32,
    reserved: u32,
};

const TagHeader = extern struct {
    tag_type: u32,
    size: u32,
};

pub const MemoryType = enum(u32) {
    available = 1,
    reserved = 2,
    acpi_reclaimable = 3,
    acpi_nvs = 4,
    bad = 5,
    _,
};

pub const MemoryMapEntry = extern struct {
    base_addr: u64,
    length: u64,
    mem_type: u32,
    reserved: u32,
};

pub const MmapTag = extern struct {
    tag_type: u32,
    size: u32,
    entry_size: u32,
    entry_version: u32,
};

inline fn align8(addr: usize) usize {
    return (addr + 7) & ~@as(usize, 7);
}

pub fn parse(mbi_addr: usize) ?TagIterator {
    if (mbi_addr == 0) return null;
    const hdr: *const MbiHeader = @ptrFromInt(mbi_addr);
    return TagIterator{ .mbi_addr = mbi_addr, .total_size = hdr.total_size, .offset = 8 };
}

pub const TagIterator = struct {
    mbi_addr: usize,
    total_size: u32,
    offset: u32,

    pub fn next(self: *TagIterator) ?*const TagHeader {
        while (self.offset < self.total_size) {
            const tag: *const TagHeader = @ptrFromInt(self.mbi_addr + self.offset);
            if (tag.tag_type == 0) return null;
            const aligned = align8(tag.size);
            if (aligned == 0) return null;
            self.offset += @as(u32, @truncate(aligned));
            return tag;
        }
        return null;
    }
};
