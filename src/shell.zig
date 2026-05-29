const console = @import("drivers/console.zig");
const wd = @import("core/watchdog.zig");
const dhcp = @import("net/dhcp.zig");
const udp = @import("net/udp.zig");
const aidaemon = @import("ai/daemon.zig");
const l2 = @import("layer2.zig");
const vfs = @import("fs/vfs.zig");
const fat32 = @import("fs/fat32.zig");
const kbd = @import("drivers/keyboard.zig");

var cwd: []const u8 = "/";
var cwd_node: ?*vfs.VfsNode = null;

pub fn process(line: []const u8) bool {
    if (line.len == 0) return true;

    if (str_eq(line, "help")) {
        console.write_str("AionOS v0.1.0-alpha");
        console.write_str("");
        console.write_str("COMMANDS:");
        console.write_str("  help     this message");
        console.write_str("  info     system information");
        console.write_str("  who      about AionOS");
        console.write_str("  crash    trigger Layer 3 crash");
        console.write_str("  mem      memory statistics");
        console.write_str("  rebuild  simulate rebuild");
        console.write_str("  clear    clear the screen");
        console.write_str("  uptime   system uptime");
        console.write_str("  echo     print text");
        console.write_str("  logo     show boot logo");
        console.write_str("  ls       list directory");
        console.write_str("  cd       change directory");
        console.write_str("  mkdir    create directory");
        console.write_str("  cat      read file");
        console.write_str("  write    write to file");
        console.write_str("  rm       delete file/dir");
        console.write_str("  edit     text editor");
        console.write_str("  net      network status");
        console.write_str("  ip       configure static IP");
        console.write_str("  ai       AI daemon status");
        console.write_str("");
    } else if (str_eq(line, "info")) {
        console.write_str("AionOS v0.1.0-alpha — System Status");
        console.write_str("  Layer 3: ");
        if (wd.is_healthy()) {
            console.write_str("    State:   ACTIVE");
        } else {
            console.write_str("    State:   CRASHED");
        }
        console.write_str("  Watchdog: Armed (100Hz)");
        if (dhcp.config.configured) {
            console.write_str("  DHCP:     Configured");
        } else {
            console.write_str("  DHCP:     Not configured");
        }
    } else if (str_eq(line, "who")) {
        console.write_str("AionOS — AI self-healing microkernel.");
        console.write_str("CPU -> Microkernel -> Layer 3 -> AI Daemon");
        console.write_str("Layer 3 crashes trigger AI analysis + hot-patch.");
        console.write_str("");
        console.write_str("Alpha release. Built by anon.");
    } else if (str_eq(line, "crash")) {
        l2.force_crash();
        return false;
    } else if (str_eq(line, "rebuild")) {
        console.write_str("AI REBUILD DEMO: 1/4..2/4..3/4..4/4 OK");
    } else if (str_eq(line, "mem")) {
        console.write_str("Heap: kmalloc/kfree active");
        console.write_str("PMM: bitmap allocator, 4KB frames");
        console.write_str("VMM: 4-level paging OK");
    } else if (str_eq(line, "clear")) {
        console.clear();
    } else if (str_eq(line, "logo")) {
        show_logo();
    } else if (str_eq(line, "uptime")) {
        console.write_str("Uptime: since boot");
    } else if (str_eq(line, "net")) {
        if (dhcp.config.configured) {
            console.write_str("DHCP: Configured");
        } else {
            console.write_str("DHCP: Not configured. Use 'ip ADDR GW DNS'");
        }
    } else if (str_starts_with(line, "ip ")) {
        set_ip(line[3..]);
    } else if (str_starts_with(line, "echo ")) {
        console.write_str(line[5..]);
    } else if (str_eq(line, "ls") or str_eq(line, "dir")) {
        do_ls();
    } else if (str_starts_with(line, "cd ")) {
        do_cd(line[3..]);
    } else if (str_eq(line, "cd")) {
        do_cd("/");
    } else if (str_starts_with(line, "mkdir ")) {
        do_mkdir(line[6..]);
    } else if (str_starts_with(line, "cat ")) {
        do_cat(line[4..]);
    } else if (str_starts_with(line, "write ")) {
        do_write(line[6..]);
    } else if (str_starts_with(line, "rm ")) {
        do_rm(line[3..]);
    } else if (str_starts_with(line, "edit ")) {
        do_edit(line[5..]);
    } else if (str_eq(line, "storage")) {
        do_storage();
    } else if (str_eq(line, "ai")) {
        if (aidaemon.config.enabled) {
            console.write_str("AI: Configured");
        } else {
            console.write_str("AI: Not configured (heuristic fallback)");
            console.write_str("Use 'ai:endpoint URL' 'ai:key KEY' 'ai:model MODEL'");
        }
    } else if (str_starts_with(line, "ai:endpoint ")) {
        set_ai_endpoint(line["ai:endpoint ".len..]);
    } else if (str_starts_with(line, "ai:key ")) {
        set_ai_key(line["ai:key ".len..]);
    } else if (str_starts_with(line, "ai:model ")) {
        set_ai_model(line["ai:model ".len..]);
    } else {
        console.write_str("? unknown command");
    }
    return true;
}

fn do_ls() void {
    if (cwd_node == null) cwd_node = vfs.find(cwd);
    const dir = cwd_node orelse return;
    var buf: [256]u8 = undefined;
    const dlen = vfs.list_dir(dir, buf[0..]);
    if (dlen > 0) {
        var start: usize = 0;
        var i: usize = 0;
        while (i <= dlen) : (i += 1) {
            if (i == dlen or buf[i] == ' ') {
                if (i > start) {
                    console.write_str(buf[start..i]);
                }
                start = i + 1;
            }
        }
    }
}

fn do_cd(path: []const u8) void {
    const trimmed = trim(path);
    if (trimmed.len == 0 or str_eq(trimmed, "/")) {
        cwd = "/";
        cwd_node = vfs.find("/");
        return;
    }
    if (str_eq(trimmed, "..")) {
        cwd = "/";
        cwd_node = vfs.find("/");
        return;
    }
    const node = vfs.find(trimmed) orelse {
        // Try relative from cwd
        var full: [128]u8 = undefined;
        var fi: usize = 0;
        for (cwd) |c| { full[fi] = c; fi += 1; }
        if (cwd[cwd.len - 1] != '/') { full[fi] = '/'; fi += 1; }
        for (trimmed) |c| { full[fi] = c; fi += 1; }
        const node2 = vfs.find(full[0..fi]) orelse {
            console.write_str("cd: no such directory");
            return;
        };
        if (node2.ftype != .dir) { console.write_str("cd: not a directory"); return; }
        cwd_node = node2;
        const name = node2.name[0..node2.name_len];
        cwd = name; // Simplified — stores just the name
        return;
    };
    if (node.ftype != .dir) { console.write_str("cd: not a directory"); return; }
    cwd_node = node;
    cwd = node.name[0..node.name_len];
}

fn do_mkdir(path: []const u8) void {
    const trimmed = trim(path);
    if (trimmed.len == 0) { console.write_str("mkdir: missing name"); return; }
    _ = vfs.create_dir(trimmed);
    console.write_str("mkdir: created");
}

fn do_cat(path: []const u8) void {
    const trimmed = trim(path);
    const node = vfs.find(trimmed) orelse {
        console.write_str("cat: file not found");
        return;
    };
    if (node.ftype != .file) { console.write_str("cat: not a file"); return; }
    var buf: [1024]u8 = undefined;
    const flen = vfs.read_file(node, buf[0..]);
    if (flen > 0) {
        // Split by lines and print
        var start: usize = 0;
        var i: usize = 0;
        while (i < flen) : (i += 1) {
            if (buf[i] == '\n' or i == flen - 1) {
                const end = if (i == flen - 1 and buf[i] != '\n') i + 1 else i;
                if (end > start) console.write_str(buf[start..end]);
                start = i + 1;
            }
        }
    }
}

fn do_write(args: []const u8) void {
    const trimmed = trim(args);
    var space: usize = 0;
    while (space < trimmed.len and trimmed[space] != ' ') : (space += 1) {}
    if (space == 0 or space >= trimmed.len) { console.write_str("write: usage: write FILE TEXT"); return; }
    const filename = trimmed[0..space];
    const text = trim(trimmed[space+1..]);

    var node = vfs.find(filename);
    if (node == null) {
        node = vfs.create_file(filename);
    }
    if (node) |n| {
        _ = vfs.write_file(n, text);
        console.write_str("write: ok");
    } else {
        console.write_str("write: failed");
    }
}

fn do_rm(path: []const u8) void {
    const trimmed = trim(path);
    if (vfs.delete_node(trimmed)) {
        console.write_str("rm: deleted");
    } else {
        console.write_str("rm: failed");
    }
}

fn do_edit(filename: []const u8) void {
    const trimmed = trim(filename);
    if (trimmed.len == 0) { console.write_str("edit: usage: edit FILE"); return; }

    var node = vfs.find(trimmed);
    if (node == null) {
        node = vfs.create_file(trimmed);
    }
    const file = node orelse { console.write_str("edit: failed"); return; };

    // Read existing content
    var content: [4096]u8 = [_]u8{0} ** 4096;
    var clen: usize = 0;
    if (file.size > 0) {
        clen = vfs.read_file(file, content[0..]);
    }

    console.write_str("");
    console.write_str("=== EDITOR ===  /q=quit  /s=save  /l=list  /dN=delete line N  /iN=insert at N");
    console.write_str("");

    var running = true;
    while (running) {
        console.write_str("> ");
        if (kbd.read_line_editor()) |line| {
            if (line.len == 0) continue;
            if (str_eq(line, "/q")) {
                running = false;
            } else if (str_eq(line, "/s")) {
                _ = vfs.write_file(file, content[0..clen]);
                console.write_str("Saved.");
            } else if (str_eq(line, "/l")) {
                list_lines(content[0..clen]);
            } else if (str_starts_with(line, "/d")) {
                const num_str = line[2..];
                const num = parse_usize(num_str);
                clen = delete_line(content[0..], clen, num);
            } else if (str_starts_with(line, "/i")) {
                const idx = parse_usize(line[2..]);
                console.write_str("(type line then Enter)");
                if (kbd.read_line_editor()) |new_line| {
                    clen = insert_line(content[0..], clen, idx, new_line);
                }
            } else {
                // Append line
                clen = append_line(content[0..], clen, line);
            }
        }
    }
    console.write_str("");
}

fn list_lines(data: []u8) void {
    var i: usize = 0;
    var ln: usize = 1;
    while (i < data.len and data[i] != 0) {
        var end = i;
        while (end < data.len and data[end] != 0 and data[end] != '\n') : (end += 1) {}
        if (end > i) {
            write_num(ln);
            console.write_str(" ");
            // Print directly
            var out_buf: [128]u8 = undefined;
            var oi: usize = 0;
            var j = i;
            while (j < end and oi < 127) : (j += 1) { out_buf[oi] = data[j]; oi += 1; }
            out_buf[oi] = 0;
            console.write_str(out_buf[0..oi]);
        }
        ln += 1;
        i = end + 1;
        if (i < data.len and data[i] == 0) break;
    }
}

fn append_line(data: []u8, len: usize, line: []const u8) usize {
    var pos = len;
    var i: usize = 0;
    while (i < line.len and pos + 1 < data.len) : (i += 1) {
        data[pos] = line[i]; pos += 1;
    }
    if (pos < data.len) { data[pos] = '\n'; pos += 1; }
    if (pos < data.len) data[pos] = 0;
    return pos;
}

fn delete_line(data: []u8, len: usize, num: usize) usize {
    if (num == 0) return len;
    var i: usize = 0;
    var ln: usize = 1;
    var line_start: usize = 0;
    while (i < len and data[i] != 0) {
        if (data[i] == '\n') {
            if (ln == num) {
                const line_end = i + 1;
                const rest = len - line_end;
                var j: usize = 0;
                while (j < rest) : (j += 1) data[line_start + j] = data[line_end + j];
                const new_len = len - (line_end - line_start);
                data[new_len] = 0;
                return new_len;
            }
            ln += 1;
            line_start = i + 1;
        }
        i += 1;
    }
    if (ln == num and i > line_start) {
        const new_len = line_start;
        data[new_len] = 0;
        return new_len;
    }
    return len;
}

fn insert_line(data: []u8, len: usize, at: usize, line: []const u8) usize {
    if (at == 0) {
        // Insert at beginning
        const new_len = len + line.len + 1;
        if (new_len >= data.len) return len;
        var j: usize = len;
        while (j > 0) : (j -= 1) data[j + line.len + 1 - 1] = data[j - 1];
        // Shift right
        var shift: usize = len + line.len;
        var si = len;
        while (si > 0) : (si -= 1) {
            if (shift < data.len and si - 1 < len) {
                data[shift] = data[si];
            }
            shift -= 1;
        }
        var i: usize = 0;
        while (i < line.len) : (i += 1) data[i] = line[i];
        data[line.len] = '\n';
        return new_len;
    }
    // Append at end for simplicity
    return append_line(data, len, line);
}

fn do_storage() void {
    console.write_str("=== Persistent Storage (FAT32) ===");
    var buf: [512]u8 = undefined;
    const len = fat32.list_root(buf[0..]);
    if (len == 0) {
        console.write_str("  (empty)");
    } else {
        // Print space-separated filenames
        var i: usize = 0;
        while (i < len) {
            // Skip spaces
            while (i < len and buf[i] == ' ') : (i += 1) {}
            if (i >= len) break;
            // Print filename
            var name_buf: [64]u8 = undefined;
            var ni: usize = 0;
            while (i < len and buf[i] != ' ' and ni < 63) : (i += 1) {
                name_buf[ni] = buf[i]; ni += 1;
            }
            console.write_str("  ");
            // Read file and show size
            if (ni > 0) {
                var fbuf: [4096]u8 = undefined;
                _ = fat32.read_file(name_buf[0..ni], fbuf[0..]);
                var out: [128]u8 = undefined;
                var oi: usize = 0;
                var j: usize = 0;
                while (j < ni and oi < 120) : (j += 1) { out[oi] = name_buf[j]; oi += 1; }
                out[oi] = 0;
                console.write_str("  ");
            }
        }
        console.write_str("");
    }
}

fn parse_usize(s: []const u8) usize {
    var v: usize = 0;
    for (s) |c| {
        if (c >= '0' and c <= '9') v = v * 10 + (c - '0');
    }
    return v;
}

fn write_num(n: usize) void {
    if (n == 0) { console.write_str("0"); return; }
    var buf: [20]u8 = undefined;
    var i: usize = 0;
    var v = n;
    while (v > 0) : (v /= 10) { buf[i] = @as(u8, @truncate(v % 10)) + '0'; i += 1; }
    while (i > 0) { i -= 1; console.write_inline(buf[i..i+1]); }
    console.write_str("");
}

fn set_ip(args: []const u8) void {
    var parts: [3][]const u8 = undefined;
    var pi: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= args.len and pi < 3) : (i += 1) {
        if (i == args.len or args[i] == ' ') {
            if (i > start) { parts[pi] = args[start..i]; pi += 1; }
            start = i + 1;
        }
    }
    if (pi >= 1) { udp.my_ip = parse_ip4(parts[0]); dhcp.config.ip = udp.my_ip; }
    if (pi >= 2) { udp.gateway_ip = parse_ip4(parts[1]); dhcp.config.gateway = udp.gateway_ip; }
    if (pi >= 3) { udp.dns_ip = parse_ip4(parts[2]); dhcp.config.dns = udp.dns_ip; }
    dhcp.config.configured = true;
    console.write_str("[NET] Static IP configured");
}

fn parse_ip4(s: []const u8) u32 {
    var ip: u32 = 0;
    var octet: u32 = 0;
    for (s) |c| {
        if (c == '.') { ip = (ip << 8) | octet; octet = 0; }
        else if (c >= '0' and c <= '9') { octet = octet * 10 + (c - '0'); }
    }
    return (ip << 8) | octet;
}

pub fn show_logo() void {
    console.write_str("       █████╗ ██╗ ██████╗ ███╗  ██╗");
    console.write_str("      ██╔══██╗██║██╔═══██╗████╗ ██║");
    console.write_str("      ███████║██║██║   ██║██╔██╗██║");
    console.write_str("      ██╔══██║██║██║   ██║██║╚████║");
    console.write_str("      ██║  ██║██║╚██████╔╝██║ ╚███║");
    console.write_str("      ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚══╝");
    console.write_str("");
    console.write_str("     AI SELF-HEALING MICROKERNEL  v0.1.0-alpha");
    console.write_str("     CPU -> Microkernel -> Layer 3 -> AI");
    console.write_str("");
}

pub fn get_prompt() []const u8 {
    _ = cwd;
    return "aion > ";
}

fn set_ai_endpoint(url: []const u8) void {
    aidaemon.set_config(url, ptr_to_slice(&aidaemon.config.api_key), ptr_to_slice(&aidaemon.config.model));
    console.write_str("[AI] Endpoint set");
}
fn set_ai_key(key: []const u8) void {
    aidaemon.set_config(ptr_to_slice(&aidaemon.config.endpoint), key, ptr_to_slice(&aidaemon.config.model));
    console.write_str("[AI] API key set");
}
fn set_ai_model(model: []const u8) void {
    aidaemon.set_config(ptr_to_slice(&aidaemon.config.endpoint), ptr_to_slice(&aidaemon.config.api_key), model);
    console.write_str("[AI] Model set");
}

fn ptr_to_slice(ptr: anytype) []const u8 {
    const p: [*]const u8 = @ptrCast(ptr);
    var len: usize = 0;
    while (len < 256 and p[len] != 0) : (len += 1) {}
    return p[0..len];
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and s[start] == ' ') : (start += 1) {}
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

fn str_eq(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, 0..) |c, i| { if (c != b[i]) return false; }
    return true;
}
fn str_starts_with(a: []const u8, prefix: []const u8) bool {
    if (a.len < prefix.len) return false;
    for (prefix, 0..) |c, i| { if (c != a[i]) return false; }
    return true;
}
