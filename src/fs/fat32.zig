const ata = @import("../drivers/ata.zig");
const console = @import("../drivers/console.zig");

var partition_lba: u32 = 0;
var sectors_per_cluster: u8 = 0;
var reserved_sectors: u16 = 0;
var num_fats: u8 = 0;
var sectors_per_fat: u32 = 0;
var root_cluster: u32 = 0;
var fat_lba: u32 = 0;
var data_lba: u32 = 0;
var mounted: bool = false;

pub fn init() bool {
    var mbr: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(0, @ptrCast(&mbr))) return false;

    var pi: usize = 446;
    while (pi < 510) : (pi += 16) {
        const ptype = mbr[pi + 4];
        if (ptype == 0x0B or ptype == 0x0C or ptype == 0x0E) {
            const lba = (@as(u32, mbr[pi + 8]) << 24) | (@as(u32, mbr[pi + 9]) << 16) | (@as(u32, mbr[pi + 10]) << 8) | mbr[pi + 11];
            if (try_mount(lba)) return true;
        }
    }
    if (try_mount(47248)) return true;
    if (try_mount(0)) return true;
    console.write_str("[FAT] No FAT32 found");
    return false;
}

fn try_mount(lba: u32) bool {
    var bpb: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(lba, @ptrCast(&bpb))) return false;
    if (((@as(u16, bpb[510]) << 8) | bpb[511]) != 0xAA55) return false;
    if (((@as(u16, bpb[11]) << 8) | bpb[12]) != 512) return false;
    if (((@as(u16, bpb[17]) << 8) | bpb[18]) != 0) return false;
    sectors_per_cluster = bpb[13];
    reserved_sectors = (@as(u16, bpb[14]) << 8) | bpb[15];
    num_fats = bpb[16];
    sectors_per_fat = (@as(u32, bpb[36]) << 24) | (@as(u32, bpb[37]) << 16) | (@as(u32, bpb[38]) << 8) | bpb[39];
    root_cluster = (@as(u32, bpb[44]) << 24) | (@as(u32, bpb[45]) << 16) | (@as(u32, bpb[46]) << 8) | bpb[47];
    partition_lba = lba;
    fat_lba = lba + reserved_sectors;
    data_lba = fat_lba + @as(u32, num_fats) * sectors_per_fat;
    mounted = true;
    console.write_str("[FAT] Mounted");
    return true;
}

fn cluster_to_lba(cluster: u32) u32 {
    return data_lba + (cluster - 2) * @as(u32, sectors_per_cluster);
}

fn read_fat_entry(cluster: u32) u32 {
    const offset = cluster * 4;
    const sector = fat_lba + offset / 512;
    const entry_off = offset % 512;
    var buf: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(sector, @ptrCast(&buf))) return 0x0FFFFFFF;
    return ((@as(u32, buf[entry_off + 3]) << 24) |
        (@as(u32, buf[entry_off + 2]) << 16) |
        (@as(u32, buf[entry_off + 1]) << 8) |
        buf[entry_off]) & 0x0FFFFFFF;
}

fn write_fat_entry(cluster: u32, value: u32) bool {
    const offset = cluster * 4;
    const sector = fat_lba + offset / 512;
    const entry_off = offset % 512;
    var buf: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(sector, @ptrCast(&buf))) return false;
    buf[entry_off] = @truncate(value);
    buf[entry_off + 1] = @truncate(value >> 8);
    buf[entry_off + 2] = @truncate(value >> 16);
    buf[entry_off + 3] = @truncate(value >> 24);
    return ata.write_sector(sector, @ptrCast(&buf));
}

fn alloc_cluster() u32 {
    var cluster: u32 = 2;
    while (cluster < sectors_per_fat * 128) : (cluster += 1) {
        if (read_fat_entry(cluster) == 0) {
            _ = write_fat_entry(cluster, 0x0FFFFFFF);
            return cluster;
        }
    }
    return 0;
}

fn free_chain(cluster: u32) void {
    var c = cluster;
    while (c < 0x0FFFFFF8) {
        const next = read_fat_entry(c);
        _ = write_fat_entry(c, 0);
        c = next;
    }
}

pub fn list_root(out: []u8) usize {
    if (!mounted) return 0;
    return read_dir(root_cluster, out);
}

fn read_dir(cluster: u32, out: []u8) usize {
    var current = cluster;
    var pos: usize = 0;
    while (current < 0x0FFFFFF8) {
        const lba = cluster_to_lba(current);
        var s: u8 = 0;
        while (s < sectors_per_cluster) : (s += 1) {
            var sector: [512]u8 = [_]u8{0} ** 512;
            if (!ata.read_sector(lba + s, @ptrCast(&sector))) return pos;
            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                if (sector[ei] == 0) return pos;
                if (sector[ei] == 0xE5) continue;
                if ((sector[ei + 11] & 0x08) != 0) continue;
                if ((sector[ei + 11] & 0x10) != 0) continue;
                var name_end: usize = 0;
                while (name_end < 8 and sector[ei + name_end] != ' ' and sector[ei + name_end] != 0) : (name_end += 1) {}
                var ni: usize = 0;
                while (ni < name_end) : (ni += 1) {
                    if (pos < out.len) out[pos] = sector[ei + ni]; pos += 1;
                }
                if (sector[ei + 8] != ' ') {
                    if (pos < out.len) out[pos] = '.'; pos += 1;
                    ni = 8;
                    while (ni < 11 and sector[ei + ni] != ' ' and sector[ei + ni] != 0) : (ni += 1) {
                        if (pos < out.len) out[pos] = sector[ei + ni]; pos += 1;
                    }
                }
                if (pos < out.len) out[pos] = ' '; pos += 1;
            }
        }
        current = read_fat_entry(current);
    }
    return pos;
}

pub fn file_exists(name: []const u8) bool {
    if (!mounted) return false;
    const entry = find_entry(root_cluster, name);
    return entry != null;
}

pub fn read_file(name: []const u8, out: []u8) usize {
    if (!mounted) return 0;
    const entry = find_entry(root_cluster, name) orelse return 0;
    const fc: u32 = (@as(u32, entry.cluster_hi) << 16) | entry.cluster_lo;
    const fs: u32 = entry.size;
    return read_clusters(fc, fs, out);
}

pub fn write_file(name: []const u8, data: []const u8) bool {
    if (!mounted) return false;

    // Delete existing file if present
    const existing = find_entry(root_cluster, name);
    if (existing != null) {
        const old_fc: u32 = (@as(u32, existing.?.cluster_hi) << 16) | existing.?.cluster_lo;
        if (old_fc >= 2) free_chain(old_fc);
        delete_entry(root_cluster, name);
    }

    // Allocate clusters
    const bytes_per_cluster = @as(u32, sectors_per_cluster) * 512;
    const needed = (data.len + bytes_per_cluster - 1) / bytes_per_cluster;
    if (needed == 0) {
        // Create empty file entry
        return create_entry(root_cluster, name, 0, 0) != null;
    }

    var first_cluster: u32 = 0;
    var prev_cluster: u32 = 0;
    var written: usize = 0;

    var ci: usize = 0;
    while (ci < needed) : (ci += 1) {
        const cluster = alloc_cluster();
        if (cluster == 0) return false;
        if (first_cluster == 0) first_cluster = cluster;
        if (prev_cluster != 0) _ = write_fat_entry(prev_cluster, cluster);
        prev_cluster = cluster;

        // Write data to this cluster
        const lba = cluster_to_lba(cluster);
        var s: u8 = 0;
        while (s < sectors_per_cluster and written < data.len) : (s += 1) {
            var sec: [512]u8 = [_]u8{0} ** 512;
            const to_copy: usize = if (data.len - written < 512) data.len - written else 512;
            var j: usize = 0;
            while (j < to_copy) : (j += 1) sec[j] = data[written + j];
            _ = ata.write_sector(lba + s, @ptrCast(&sec));
            written += to_copy;
        }
    }

    _ = create_entry(root_cluster, name, first_cluster, @truncate(data.len));
    return true;
}

fn read_clusters(start: u32, size: u32, out: []u8) usize {
    var cluster = start;
    var remaining = size;
    var pos: usize = 0;
    while (cluster < 0x0FFFFFF8 and remaining > 0 and pos < out.len) {
        const lba = cluster_to_lba(cluster);
        var s: u8 = 0;
        while (s < sectors_per_cluster and remaining > 0 and pos < out.len) : (s += 1) {
            var data: [512]u8 = undefined;
            if (!ata.read_sector(lba + s, @ptrCast(&data))) return pos;
            const to_copy: usize = if (remaining < 512) remaining else 512;
            const copy = if (to_copy < out.len - pos) to_copy else out.len - pos;
            var j: usize = 0;
            while (j < copy) : (j += 1) out[pos + j] = data[j];
            pos += copy;
            remaining -%= @as(u32, @truncate(copy));
        }
        cluster = read_fat_entry(cluster);
    }
    return pos;
}

const DirEntry = struct {
    cluster_lo: u16,
    cluster_hi: u16,
    size: u32,
};

fn find_entry(dir_cluster: u32, name: []const u8) ?DirEntry {
    var current = dir_cluster;
    while (current < 0x0FFFFFF8) {
        const lba = cluster_to_lba(current);
        var s: u8 = 0;
        while (s < sectors_per_cluster) : (s += 1) {
            var sector: [512]u8 = [_]u8{0} ** 512;
            if (!ata.read_sector(lba + s, @ptrCast(&sector))) return null;
            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                if (sector[ei] == 0) return null;
                if (sector[ei] == 0xE5) continue;
                if ((sector[ei + 11] & 0x10) != 0) continue;
                var fn_buf: [13]u8 = undefined;
                var fni: usize = 0;
                var di: usize = 0;
                while (di < 8 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) { fn_buf[fni] = sector[ei + di]; fni += 1; }
                if (sector[ei + 8] != ' ') { fn_buf[fni] = '.'; fni += 1; di = 8;
                    while (di < 11 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) { fn_buf[fni] = sector[ei + di]; fni += 1; }
                }
                if (str_eq(fn_buf[0..fni], name)) {
                    return DirEntry{
                        .cluster_lo = (@as(u16, sector[ei + 26]) << 8) | sector[ei + 27],
                        .cluster_hi = (@as(u16, sector[ei + 20]) << 8) | sector[ei + 21],
                        .size = (@as(u32, sector[ei + 28]) << 24) | (@as(u32, sector[ei + 29]) << 16) | (@as(u32, sector[ei + 30]) << 8) | sector[ei + 31],
                    };
                }
            }
        }
        current = read_fat_entry(current);
    }
    return null;
}

fn delete_entry(dir_cluster: u32, name: []const u8) void {
    var current = dir_cluster;
    while (current < 0x0FFFFFF8) {
        const lba = cluster_to_lba(current);
        var s: u8 = 0;
        while (s < sectors_per_cluster) : (s += 1) {
            var sector: [512]u8 = [_]u8{0} ** 512;
            if (!ata.read_sector(lba + s, @ptrCast(&sector))) return;
            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                if (sector[ei] == 0) return;
                var fn_buf: [13]u8 = undefined;
                var fni: usize = 0;
                var di: usize = 0;
                while (di < 8 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) { fn_buf[fni] = sector[ei + di]; fni += 1; }
                if (sector[ei + 8] != ' ') { fn_buf[fni] = '.'; fni += 1; di = 8;
                    while (di < 11 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) { fn_buf[fni] = sector[ei + di]; fni += 1; }
                }
                if (str_eq(fn_buf[0..fni], name)) {
                    sector[ei] = 0xE5;
                    _ = ata.write_sector(lba + s, @ptrCast(&sector));
                    return;
                }
            }
        }
        current = read_fat_entry(current);
    }
}

fn create_entry(dir_cluster: u32, name: []const u8, cluster: u32, size: u32) ?DirEntry {
    // Find free directory entry slot
    var current = dir_cluster;
    while (current < 0x0FFFFFF8) {
        const lba = cluster_to_lba(current);
        var s: u8 = 0;
        while (s < sectors_per_cluster) : (s += 1) {
            var sector: [512]u8 = [_]u8{0} ** 512;
            if (!ata.read_sector(lba + s, @ptrCast(&sector))) return null;
            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                if (sector[ei] == 0 or sector[ei] == 0xE5) {
                    // Fill entry
                    // Convert name to 8.3 format
                    var dot: isize = -1;
                    var ni: usize = 0;
                    while (ni < name.len) : (ni += 1) { if (name[ni] == '.') { dot = @intCast(ni); break; } }
                    const base_len: usize = if (dot >= 0) @intCast(dot) else name.len;
                    const ext_start: usize = if (dot >= 0) @intCast(dot + 1) else name.len;

                    // Clear entry
                    var x: usize = 0;
                    while (x < 32) : (x += 1) sector[ei + x] = 0;

                    // Name (padded with spaces)
                    var bn: usize = 0;
                    while (bn < 8) : (bn += 1) {
                        sector[ei + bn] = if (bn < base_len) upper(name[bn]) else ' ';
                    }
                    // Extension
                    var en: usize = 0;
                    while (en < 3) : (en += 1) {
                        sector[ei + 8 + en] = if (ext_start + en < name.len) upper(name[ext_start + en]) else ' ';
                    }
                    sector[ei + 11] = 0x20; // Archive attribute
                    sector[ei + 26] = @truncate(cluster);
                    sector[ei + 27] = @truncate(cluster >> 8);
                    sector[ei + 20] = @truncate(cluster >> 16);
                    sector[ei + 21] = @truncate(cluster >> 24);
                    sector[ei + 28] = @truncate(size);
                    sector[ei + 29] = @truncate(size >> 8);
                    sector[ei + 30] = @truncate(size >> 16);
                    sector[ei + 31] = @truncate(size >> 24);

                    _ = ata.write_sector(lba + s, @ptrCast(&sector));
                    return DirEntry{ .cluster_lo = @truncate(cluster), .cluster_hi = @truncate(cluster >> 16), .size = size };
                }
            }
        }
        current = read_fat_entry(current);
    }
    return null;
}

fn upper(c: u8) u8 {
    if (c >= 'a' and c <= 'z') return c - 32;
    return c;
}

fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| { if (c != b[i]) return false; }
    return true;
}
