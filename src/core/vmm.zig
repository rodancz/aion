const pmm = @import("pmm.zig");
const kmalloc = @import("kmalloc.zig");
const serial = @import("../drivers/serial.zig");

const PAGE_SIZE: usize = 4096;
pub const PAGE_PRESENT: u64 = 1 << 0;
pub const PAGE_RW: u64 = 1 << 1;
pub const PAGE_USER: u64 = 1 << 2;
const PAGE_HUGE: u64 = 1 << 7;
const PAGE_NX: u64 = 1 << 63;

pub const PageFlags = packed struct(u64) {
    present: bool,
    writable: bool,
    user: bool,
    _pwt: bool,
    _pcd: bool,
    _accessed: bool,
    _dirty: bool,
    huge: bool,
    _global: bool,
    _avail: u3 = 0,
    addr: u40 = 0,
    _avail2: u11 = 0,
    no_exec: bool = false,
};

pub const AddressSpace = struct {
    pml4_phys: usize,
};

pub fn create_space() ?AddressSpace {
    const pml4_phys = pmm.alloc_frame() orelse return null;
    const pml4: [*]volatile u64 = @ptrFromInt(pml4_phys);
    var i: usize = 0;
    while (i < 512) : (i += 1) {
        pml4[i] = 0;
    }

    const kernel_pml4: [*]const u64 = @ptrFromInt(get_current_space());
    i = 0;
    while (i < 512) : (i += 1) {
        pml4[i] = kernel_pml4[i];
    }

    return AddressSpace{ .pml4_phys = pml4_phys };
}

pub fn get_current_space() usize {
    var cr3: usize = undefined;
    asm volatile ("mov %%cr3, %[out]"
        : [out] "=r" (cr3),
    );
    return cr3;
}

fn get_or_create_table(table: [*]volatile u64, index: usize, flags: u64) ?usize {
    if (table[index] & PAGE_PRESENT == 0) {
        const page = pmm.alloc_frame() orelse return null;
        var p: usize = 0;
        const new_table: [*]volatile u64 = @ptrFromInt(page);
        while (p < 512) : (p += 1) {
            new_table[p] = 0;
        }
        table[index] = (page & 0x000FFFFFFFFFF000) | flags | PAGE_PRESENT | PAGE_RW | PAGE_USER;
    }
    return @truncate(table[index] & 0x000FFFFFFFFFF000);
}

pub fn map_page(space: AddressSpace, virt: usize, phys: usize, flags: u64) bool {
    const pml4_idx = (virt >> 39) & 0x1FF;
    const pdpt_idx = (virt >> 30) & 0x1FF;
    const pd_idx = (virt >> 21) & 0x1FF;
    const pt_idx = (virt >> 12) & 0x1FF;

    const pml4: [*]volatile u64 = @ptrFromInt(space.pml4_phys);

    const pdpt_phys = get_or_create_table(pml4, pml4_idx, flags) orelse return false;
    const pdpt: [*]volatile u64 = @ptrFromInt(pdpt_phys);

    const pd_phys = get_or_create_table(pdpt, pdpt_idx, flags) orelse return false;
    const pd: [*]volatile u64 = @ptrFromInt(pd_phys);

    const pt_phys = get_or_create_table(pd, pd_idx, flags) orelse return false;
    const pt: [*]volatile u64 = @ptrFromInt(pt_phys);

    pt[pt_idx] = (phys & 0x000FFFFFFFFFF000) | flags | PAGE_PRESENT;

    return true;
}

pub fn switch_to(space: AddressSpace) void {
    asm volatile (
        \\ mov %[cr3], %%cr3
        :
        : [cr3] "r" (space.pml4_phys),
        : .{ .memory = true }
    );
}
