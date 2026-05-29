const kmalloc = @import("../core/kmalloc.zig");
const console = @import("../drivers/console.zig");

const MAX_FILES: usize = 64;
const MAX_NAME: usize = 32;
const BLOCK_SIZE: usize = 512;
const MAX_BLOCKS: usize = 8;

const FileType = enum(u8) {
    file = 0,
    dir = 1,
};

pub const VfsNode = struct {
    name: [MAX_NAME]u8,
    name_len: usize,
    ftype: FileType,
    parent: ?*VfsNode,
    children: ?*VfsNode, // linked list of children (for dirs)
    next: ?*VfsNode,     // next sibling
    blocks: [MAX_BLOCKS][*]u8, // data blocks
    block_count: usize,
    size: usize,
};

var root: ?*VfsNode = null;
var node_count: usize = 0;

pub fn init() void {
    root = alloc_node("/", .dir);
    if (root == null) {
        console.write_str("[FS] Failed to allocate root");
        return;
    }
    console.write_str("[FS] VFS initialized");
}

fn alloc_node(name: []const u8, ftype: FileType) ?*VfsNode {
    if (node_count >= MAX_FILES) return null;
    const mem = kmalloc.kmalloc(@sizeOf(VfsNode)) orelse return null;
    const node: *VfsNode = @ptrCast(@alignCast(mem));
    node.ftype = ftype;
    node.parent = null;
    node.children = null;
    node.next = null;
    node.block_count = 0;
    node.size = 0;
    node.name_len = if (name.len < MAX_NAME) name.len else MAX_NAME - 1;
    var i: usize = 0;
    while (i < node.name_len) : (i += 1) node.name[i] = name[i];
    node.name[node.name_len] = 0;
    i = 0;
    while (i < MAX_BLOCKS) : (i += 1) node.blocks[i] = undefined;
    node_count += 1;
    return node;
}

pub fn create_file(path: []const u8) ?*VfsNode {
    return create_node(path, .file);
}

pub fn create_dir(path: []const u8) ?*VfsNode {
    return create_node(path, .dir);
}

fn create_node(path: []const u8, ftype: FileType) ?*VfsNode {
    const parent_opt = resolve_parent(path) orelse return null;
    const parent = parent_opt;
    const name = basename(path);
    if (name.len == 0) return null;

    // Check if already exists
    var child = parent.children;
    while (child) |c| : (child = c.next) {
        if (str_eq(c.name[0..c.name_len], name)) return null;
    }

    const node = alloc_node(name, ftype) orelse return null;
    node.parent = parent_opt;
    node.next = parent.children;
    parent.children = node;
    return node;
}

pub fn find(path: []const u8) ?*VfsNode {
    if (path.len == 0) return null;
    const start: usize = if (path[0] == '/') @as(usize, 1) else @as(usize, 0);
    if (start >= path.len) return root;

    var current = root;
    var i = start;
    while (i < path.len) {
        var end = i;
        while (end < path.len and path[end] != '/') : (end += 1) {}
        const name = path[i..end];
        if (name.len == 0) break;

        if (current) |dir| {
            var found: bool = false;
            var child = dir.children;
            while (child) |c| : (child = c.next) {
                if (str_eq(c.name[0..c.name_len], name)) {
                    current = c;
                    found = true;
                    break;
                }
            }
            if (!found) return null;
        } else {
            return null;
        }
        i = end + 1;
    }
    return current;
}

fn resolve_parent(path: []const u8) ?*VfsNode {
    if (path.len == 0) return null;
    if (path[0] != '/') {
        // Relative path — use root for now
        return root;
    }
    var last_slash: usize = path.len;
    var j: usize = path.len;
    while (j > 0) : (j -= 1) {
        if (path[j - 1] == '/') {
            last_slash = j - 1;
            break;
        }
    }
    if (last_slash == 0) return root;
    const parent_path = path[0..last_slash];
    return find(parent_path);
}

fn basename(path: []const u8) []const u8 {
    var j: usize = path.len;
    while (j > 0) : (j -= 1) {
        if (path[j - 1] == '/') return path[j..];
    }
    return path;
}

pub fn write_file(node: *VfsNode, data: []const u8) bool {
    if (node.ftype != .file) return false;
    node.block_count = 0;
    node.size = 0;

    var remaining = data.len;
    var di: usize = 0;
    while (remaining > 0 and node.block_count < MAX_BLOCKS) : (di += BLOCK_SIZE) {
        const block = kmalloc.kmalloc(BLOCK_SIZE) orelse return false;
        const buf: [*]u8 = @ptrCast(@alignCast(block));
        const copy = if (remaining < BLOCK_SIZE) remaining else BLOCK_SIZE;
        var i: usize = 0;
        while (i < copy) : (i += 1) buf[i] = data[di + i];
        node.blocks[node.block_count] = buf;
        node.block_count += 1;
        node.size += copy;
        remaining -= copy;
    }
    return remaining == 0;
}

pub fn read_file(node: *VfsNode, out: []u8) usize {
    if (node.ftype != .file) return 0;
    var total: usize = 0;
    var bi: usize = 0;
    while (bi < node.block_count and total < out.len) : (bi += 1) {
        const block_size = if (bi == node.block_count - 1 and node.size % BLOCK_SIZE != 0) node.size % BLOCK_SIZE else BLOCK_SIZE;
        const copy = if (block_size < out.len - total) block_size else out.len - total;
        var i: usize = 0;
        while (i < copy) : (i += 1) out[total + i] = node.blocks[bi][i];
        total += copy;
    }
    return total;
}

pub fn delete_node(path: []const u8) bool {
    const node_opt = find(path) orelse return false;
    const node = node_opt;
    if (node == root) return false;

    // Free blocks
    var bi: usize = 0;
    while (bi < node.block_count) : (bi += 1) {
        kmalloc.kfree(node.blocks[bi]);
    }

    // Remove from parent's children list
    const parent = node.parent orelse return false;
    if (parent.children == node) {
        parent.children = node.next;
    } else {
        var prev = parent.children;
        while (prev) |p| : (prev = p.next) {
            if (p.next == node) {
                p.next = node.next;
                break;
            }
        }
    }

    kmalloc.kfree(node);
    node_count -= 1;
    return true;
}

pub fn list_dir(node: *VfsNode, buf: []u8) usize {
    if (node.ftype != .dir) return 0;
    var pos: usize = 0;
    var child = node.children;
    while (child) |c| : (child = c.next) {
        const suffix: []const u8 = if (c.ftype == .dir) "/" else "";
        const total = c.name_len + suffix.len + 2; // space + suffix
        if (pos + total >= buf.len) break;
        if (pos > 0) { buf[pos] = ' '; pos += 1; }
        var i: usize = 0;
        while (i < c.name_len) : (i += 1) { buf[pos] = c.name[i]; pos += 1; }
        i = 0;
        while (i < suffix.len) : (i += 1) { buf[pos] = suffix[i]; pos += 1; }
    }
    return pos;
}

pub fn get_child(node: *VfsNode, name: []const u8) ?*VfsNode {
    var child = node.children;
    while (child) |c| : (child = c.next) {
        if (str_eq(c.name[0..c.name_len], name)) return c;
    }
    return null;
}

fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| { if (c != b[i]) return false; }
    return true;
}
