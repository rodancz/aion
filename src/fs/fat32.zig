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
    // Read MBR and find first partition
    var mbr: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(0, @ptrCast(&mbr))) return false;

    // Check partition table entries (at offset 446)
    var pi: usize = 446;
    while (pi < 510) : (pi += 16) {
        const ptype = mbr[pi + 4];
        if (ptype == 0x0B or ptype == 0x0C or ptype == 0x0E) {
            partition_lba = (@as(u32, mbr[pi + 8]) << 24) | (@as(u32, mbr[pi + 9]) << 16) | (@as(u32, mbr[pi + 10]) << 8) | mbr[pi + 11];
            break;
        }
    }
    if (partition_lba == 0) {
        // No partition table — try reading BPB from sector 0 (superfloppy)
        partition_lba = 0;
    }

    // Read BPB
    var bpb: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(partition_lba, @ptrCast(&bpb))) return false;

    sectors_per_cluster = bpb[13];
    reserved_sectors = (@as(u16, bpb[14]) << 8) | bpb[15];
    num_fats = bpb[16];
    sectors_per_fat = (@as(u32, bpb[36]) << 24) | (@as(u32, bpb[37]) << 16) | (@as(u32, bpb[38]) << 8) | bpb[39];
    root_cluster = (@as(u32, bpb[44]) << 24) | (@as(u32, bpb[45]) << 16) | (@as(u32, bpb[46]) << 8) | bpb[47];

    fat_lba = partition_lba + reserved_sectors;
    data_lba = fat_lba + @as(u32, num_fats) * sectors_per_fat;

    mounted = true;
    console.write_str("[FAT] Mounted");
    return true;
}

fn cluster_to_lba(cluster: u32) u32 {
    return data_lba + (cluster - 2) * @as(u32, sectors_per_cluster);
}

fn next_cluster(cluster: u32) u32 {
    const fat_offset = cluster * 4;
    const fat_sector = fat_lba + fat_offset / 512;
    const fat_entry_offset = fat_offset % 512;

    var fat_buf: [512]u8 = [_]u8{0} ** 512;
    if (!ata.read_sector(fat_sector, @ptrCast(&fat_buf))) return 0x0FFFFFFF;

    const entry = (@as(u32, fat_buf[fat_entry_offset + 3]) << 24) |
        (@as(u32, fat_buf[fat_entry_offset + 2]) << 16) |
        (@as(u32, fat_buf[fat_entry_offset + 1]) << 8) |
        fat_buf[fat_entry_offset];

    return entry & 0x0FFFFFFF;
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
            _ = ata.read_sector(lba + s, @ptrCast(&sector));

            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                const first_byte = sector[ei];
                if (first_byte == 0) return pos; // end of directory
                if (first_byte == 0xE5 or first_byte == '.') continue; // deleted or dot entries
                if ((sector[ei + 11] & 0x08) != 0) continue; // volume label
                if ((sector[ei + 11] & 0x10) != 0) continue; // directory (skip for now)

                // Get filename (8 chars + 3 chars extension)
                var name_len: usize = 0;
                var ni: usize = 0;
                while (ni < 8 and sector[ei + ni] != ' ' and sector[ei + ni] != 0) : (ni += 1) {
                    if (pos + name_len < out.len) {
                        out[pos + name_len] = sector[ei + ni];
                    }
                    name_len += 1;
                }
                // Extension
                if (sector[ei + 8] != ' ') {
                    if (pos + name_len < out.len) out[pos + name_len] = '.';
                    name_len += 1;
                    ni = 8;
                    while (ni < 11 and sector[ei + ni] != ' ' and sector[ei + ni] != 0) : (ni += 1) {
                        if (pos + name_len < out.len) out[pos + name_len] = sector[ei + ni];
                        name_len += 1;
                    }
                }
                if (pos + name_len < out.len) { out[pos + name_len] = ' '; }
                name_len += 1;
                pos += name_len;
            }
        }
        current = next_cluster(current);
    }
    return pos;
}

pub fn read_file(name: []const u8, out: []u8) usize {
    if (!mounted) return 0;

    // Search root directory for file
    var current = root_cluster;
    while (current < 0x0FFFFFF8) {
        const lba = cluster_to_lba(current);
        var s: u8 = 0;
        while (s < sectors_per_cluster) : (s += 1) {
            var sector: [512]u8 = [_]u8{0} ** 512;
            _ = ata.read_sector(lba + s, @ptrCast(&sector));

            var ei: usize = 0;
            while (ei < 512) : (ei += 32) {
                if (sector[ei] == 0) return 0;
                if (sector[ei] == 0xE5) continue;
                if ((sector[ei + 11] & 0x10) != 0) continue;

                // Compare name
                var name_buf: [12]u8 = undefined;
                var ni: usize = 0;
                var di: usize = 0;
                while (di < 8 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) {
                    name_buf[ni] = sector[ei + di]; ni += 1;
                }
                if (sector[ei + 8] != ' ') {
                    name_buf[ni] = '.'; ni += 1;
                    di = 8;
                    while (di < 11 and sector[ei + di] != ' ' and sector[ei + di] != 0) : (di += 1) {
                        name_buf[ni] = sector[ei + di]; ni += 1;
                    }
                }
                name_buf[ni] = 0;

                if (!str_eq(name_buf[0..ni], name)) continue;

                // Found file — read clusters
                const file_cluster = (@as(u32, sector[ei + 20]) << 16) | (@as(u32, sector[ei + 26]) << 8) | sector[ei + 27];
                const file_size = (@as(u32, sector[ei + 28]) << 24) | (@as(u32, sector[ei + 29]) << 16) | (@as(u32, sector[ei + 30]) << 8) | sector[ei + 31];

                var fc = file_cluster;
                var out_pos: usize = 0;
                while (fc < 0x0FFFFFF8 and out_pos < file_size and out_pos < out.len) {
                    const clba = cluster_to_lba(fc);
                    var cs: u8 = 0;
                    while (cs < sectors_per_cluster and out_pos < file_size and out_pos < out.len) : (cs += 1) {
                        var data: [512]u8 = undefined;
                        _ = ata.read_sector(clba + cs, @ptrCast(&data));
                        const to_copy: usize = if (file_size - out_pos < 512) file_size - out_pos else 512;
                        var j: usize = 0;
                        while (j < to_copy and out_pos + j < out.len) : (j += 1) {
                            out[out_pos + j] = data[j];
                        }
                        out_pos += to_copy;
                    }
                    fc = next_cluster(fc);
                }
                return out_pos;
            }
        }
        current = next_cluster(current);
    }
    return 0;
}

fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| { if (c != b[i]) return false; }
    return true;
}
