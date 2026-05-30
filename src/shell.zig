const console = @import("drivers/console.zig");
const wd = @import("core/watchdog.zig");
const dhcp = @import("net/dhcp.zig");
const udp = @import("net/udp.zig");
const aidaemon = @import("ai/daemon.zig");
const l2 = @import("layer2.zig");
const vfs = @import("fs/vfs.zig");
const fat32 = @import("fs/fat32.zig");
const kbd = @import("drivers/keyboard.zig");
const isr = @import("arch/x86_64/isr.zig");

var cwd: []const u8 = "/";
var cwd_node: ?*vfs.VfsNode = null;

pub fn process(line: []const u8) bool {
    if (line.len == 0) return true;
    if (str_eq(line, "help")) { return do_help(); }
    if (str_eq(line, "info")) { return do_info(); }
    if (str_eq(line, "who")) { return do_who(); }
    if (str_eq(line, "crash")) { l2.force_crash(); return false; }
    if (str_eq(line, "rebuild")) { console.write_str("Recovery: Layer 3 is ACTIVE"); }
    if (str_eq(line, "modules")) { do_modules(); return true; }
    if (str_eq(line, "upgrade")) { l2.upgrade_module(); return true; }
    else if (str_eq(line, "mem")) { do_mem(); }
    else if (str_eq(line, "clear")) { console.clear(); }
    else if (str_eq(line, "logo")) { show_logo(); }
    else if (str_eq(line, "uptime")) { do_uptime(); }
    else if (str_eq(line, "net")) { do_net(); }
    else if (str_eq(line, "ai")) { do_ai(); }
    else if (str_eq(line, "ver")) { console.write_str("AionOS v0.1.0-alpha"); }
    else if (str_eq(line, "reboot")) { do_reboot(); }
    else if (str_eq(line, "pci")) { do_pci(); }
    else if (str_starts_with(line, "ip ")) { set_ip(line[3..]); }
    else if (str_starts_with(line, "echo ")) { console.write_str(line[5..]); }
    else if (str_eq(line, "ls") or str_eq(line, "dir")) { do_ls(); }
    else if (str_starts_with(line, "cd ")) { do_cd(line[3..]); }
    else if (str_eq(line, "cd")) { do_cd("/"); }
    else if (str_starts_with(line, "mkdir ")) { do_mkdir(line[6..]); }
    else if (str_starts_with(line, "cat ")) { do_cat(line[4..]); }
    else if (str_starts_with(line, "write ")) { do_write(line[6..]); }
    else if (str_starts_with(line, "rm ")) { do_rm(line[3..]); }
    else if (str_starts_with(line, "edit ")) { do_edit(line[5..]); }
    else if (str_eq(line, "storage")) { do_storage(); }
    else if (str_starts_with(line, "save ")) { do_save(line[5..]); }
    else if (str_starts_with(line, "load ")) { do_load(line[5..]); }
    else if (str_starts_with(line, "ai:endpoint ")) { set_ai_endpoint(line["ai:endpoint ".len..]); }
    else if (str_starts_with(line, "ai:key ")) { set_ai_key(line["ai:key ".len..]); }
    else if (str_starts_with(line, "ai:model ")) { set_ai_model(line["ai:model ".len..]); }
    else { console.write_str("? unknown command"); }
    return true;
}

fn do_help() bool {
    console.write_str("AionOS v0.1.0-alpha");
    console.write_str("");
    console.write_str("FILES:  ls  cd  mkdir  cat  write  rm  edit");
    console.write_str("DISK:   storage  save  load");
    console.write_str("SYS:    info  who  mem  uptime  ver  clear  logo  reboot");
    console.write_str("L3:     modules  upgrade  crash  rebuild");
    console.write_str("NET:    net  ip  ai");
    console.write_str("");
    return true;
}
fn do_info() bool {
    console.write_str("AionOS v0.1.0-alpha — System Status");
    console.write_str("  Layer 3: ");
    if (wd.is_healthy()) console.write_str("    ACTIVE") else console.write_str("    CRASHED");
    console.write_str("  Module:   ");
    console.write_str(l2.get_module_name());
    console.write_str("  Upgrades: ");
    {
        const uc = l2.get_upgrade_count();
        const digits = "0123456789";
        var ubuf: [20]u8 = undefined;
        var un: u64 = uc;
        var ui: usize = 0;
        if (un == 0) { ubuf[0] = '0'; ui = 1; }
        while (un > 0 and ui < 20) : (un /= 10) { ubuf[ui] = digits[@intCast(un % 10)]; ui += 1; }
        var us: usize = 0;
        var ue: usize = ui;
        while (us < ue) : ({ us += 1; ue -= 1; }) { const ut = ubuf[us]; ubuf[us] = ubuf[ue-1]; ubuf[ue-1] = ut; }
        console.write_inline(ubuf[0..ui]);
    }
    const cc = wd.get_crash_count();
    if (cc > 0) {
        console.write_str("");
        console.write_str("  Crashes:  ");
        const digits = "0123456789";
        var buf: [20]u8 = undefined;
        var n: u64 = cc;
        var i: usize = 0;
        if (n == 0) { buf[0] = '0'; i = 1; }
        while (n > 0 and i < 20) : (n /= 10) { buf[i] = digits[@intCast(n % 10)]; i += 1; }
        var s: usize = 0;
        var e: usize = i;
        while (s < e) : ({ s += 1; e -= 1; }) {
            const tmp = buf[s];
            buf[s] = buf[e - 1];
            buf[e - 1] = tmp;
        }
        console.write_inline(buf[0..i]);
        console.write_str("");
        console.write_str("  Last:     ");
        console.write_inline(wd.get_last_crash());
    }
    console.write_str("  Watchdog: Armed (100Hz)");
    if (dhcp.config.configured) console.write_str("  DHCP:     Configured") else console.write_str("  DHCP:     Not configured");
    return true;
}
fn do_pci() void {
    const pci_mod = @import("bus/pci.zig");
    const count = pci_mod.scan_all();
    if (count > 0) console.write_str("PCI devices found") else console.write_str("No PCI devices");
}
fn do_modules() void {
    const active = l2.get_module();
    for (l2.MODULES) |mod| {
        if (active.version == mod.version) {
            console.write_inline("  > ");
        } else {
            console.write_inline("    ");
        }
        console.write_inline(mod.name);
        if (active.version == mod.version) {
            console.write_str(" (active)");
        } else {
            console.write_str("");
        }
    }
}
fn do_who() bool {
    console.write_str("AionOS — AI self-healing microkernel.");
    console.write_str("CPU -> Microkernel -> Layer 3 -> AI Daemon");
    console.write_str("Layer 3 crashes trigger AI analysis + hot-patch.");
    console.write_str("Alpha release. Built by anon.");
    return true;
}
fn do_mem() void {
    console.write_str("Heap: kmalloc/kfree active");
    console.write_str("PMM: bitmap, 4KB frames");
    console.write_str("VMM: 4-level paging OK");
}
fn do_uptime() void {
    const ticks = isr.get_ticks();
    const secs = ticks / 100;
    if (secs < 60) { console.write_str("Uptime: just now"); }
    else if (secs < 3600) { console.write_str("Uptime: a few minutes"); }
    else { console.write_str("Uptime: a while"); }
}
fn do_net() void {
    if (dhcp.config.configured) console.write_str("DHCP: Configured")
    else console.write_str("DHCP: Not configured. Use 'ip ADDR GW DNS'");
}
fn do_ai() void {
    if (aidaemon.config.enabled) console.write_str("AI: Configured")
    else console.write_str("AI: Not configured (local classification)");
    console.write_str("  Last action: ");
    console.write_str(aidaemon.action_name(aidaemon.get_action()));
    const cc = wd.get_crash_count();
    if (cc > 0) {
        console.write_str("  Crashes handled: ");
        const digits = "0123456789";
        var buf: [20]u8 = undefined;
        var n: u64 = cc;
        var i: usize = 0;
        if (n == 0) { buf[0] = '0'; i = 1; }
        while (n > 0 and i < 20) : (n /= 10) {
            buf[i] = digits[@intCast(n % 10)];
            i += 1;
        }
        var s: usize = 0;
        var e: usize = i;
        while (s < e) : ({ s += 1; e -= 1; }) {
            const tmp = buf[s];
            buf[s] = buf[e - 1];
            buf[e - 1] = tmp;
        }
        console.write_str(buf[0..i]);
    } else {
        console.write_str("  Crashes: 0");
    }
}
fn do_reboot() void {
    console.write_str("Rebooting via triple fault...");
    asm volatile ("int $0x80"); // Will fault
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
                if (i > start) console.write_str(buf[start..i]);
                start = i + 1;
            }
        }
    }
}
fn do_cd(path: []const u8) void {
    const trimmed = trim(path);
    if (trimmed.len == 0 or str_eq(trimmed, "/")) { cwd = "/"; cwd_node = vfs.find("/"); return; }
    if (str_eq(trimmed, "..")) { cwd = "/"; cwd_node = vfs.find("/"); return; }
    const node = vfs.find(trimmed) orelse { console.write_str("cd: no such dir"); return; };
    if (node.ftype != .dir) { console.write_str("cd: not a dir"); return; }
    cwd_node = node;
    cwd = node.name[0..node.name_len];
}
fn do_mkdir(path: []const u8) void { _ = vfs.create_dir(trim(path)); console.write_str("ok"); }
fn do_cat(path: []const u8) void {
    const node = vfs.find(trim(path)) orelse { console.write_str("cat: not found"); return; };
    if (node.ftype != .file) { console.write_str("cat: not a file"); return; }
    var buf: [1024]u8 = undefined;
    const flen = vfs.read_file(node, buf[0..]);
    var start: usize = 0;
    var i: usize = 0;
    while (i < flen) : (i += 1) {
        if (buf[i] == '\n' or i == flen - 1) {
            const end = if (i == flen - 1 and buf[i] != '\n') i + 1 else i;
            if (end > start) { console.write_str(buf[start..end]); }
            start = i + 1;
        }
    }
}
fn do_write(args: []const u8) void {
    const t = trim(args);
    var sp: usize = 0;
    while (sp < t.len and t[sp] != ' ') : (sp += 1) {}
    if (sp == 0 or sp >= t.len) { console.write_str("usage: write FILE TEXT"); return; }
    const fn2 = t[0..sp];
    const text = trim(t[sp+1..]);
    var node = vfs.find(fn2);
    if (node == null) node = vfs.create_file(fn2);
    if (node) |n| { _ = vfs.write_file(n, text); console.write_str("ok"); }
    else { console.write_str("failed"); }
}
fn do_rm(path: []const u8) void {
    if (vfs.delete_node(trim(path))) console.write_str("ok") else console.write_str("failed");
}

fn do_storage() void {
    console.write_str("=== Persistent Storage ===");
    var buf: [256]u8 = undefined;
    const len = fat32.list_root(buf[0..]);
    if (len == 0) { console.write_str("  (empty)"); return; }
    var i: usize = 0;
    while (i < len) {
        while (i < len and buf[i] == ' ') : (i += 1) {}
        if (i >= len) break;
        var name: [64]u8 = undefined;
        var ni: usize = 0;
        while (i < len and buf[i] != ' ' and ni < 63) : (i += 1) { name[ni] = buf[i]; ni += 1; }
        if (ni > 0) {
            var fbuf: [4096]u8 = undefined;
            _ = fat32.read_file(name[0..ni], fbuf[0..]);
            var out: [96]u8 = undefined;
            var oi: usize = 0;
            out[oi] = ' '; oi += 1; out[oi] = ' '; oi += 1;
            var j: usize = 0;
            while (j < ni and oi < 90) : (j += 1) { out[oi] = name[j]; oi += 1; }
            console.write_str(out[0..oi]);
        }
    }
}

fn do_save(filename: []const u8) void {
    const t = trim(filename);
    if (t.len == 0) { console.write_str("usage: save FILENAME"); return; }
    const node = vfs.find(t) orelse { console.write_str("save: VFS file not found"); return; };
    if (node.ftype != .file) { console.write_str("save: not a file"); return; }
    var buf: [4096]u8 = undefined;
    const len = vfs.read_file(node, buf[0..]);
    if (len == 0) { console.write_str("save: empty file"); return; }
    if (fat32.write_file(t, buf[0..len])) console.write_str("saved to disk") else console.write_str("save: disk write failed");
}
fn do_load(filename: []const u8) void {
    const t = trim(filename);
    if (t.len == 0) { console.write_str("usage: load FILENAME"); return; }
    var buf: [4096]u8 = undefined;
    const len = fat32.read_file(t, buf[0..]);
    if (len == 0) { console.write_str("load: not found on disk"); return; }
    var node = vfs.find(t);
    if (node == null) node = vfs.create_file(t);
    if (node) |n| { _ = vfs.write_file(n, buf[0..len]); console.write_str("loaded from disk"); }
    else { console.write_str("load: failed"); }
}

fn do_edit(filename: []const u8) void {
    const t = trim(filename);
    if (t.len == 0) { console.write_str("usage: edit FILE"); return; }
    var node = vfs.find(t);
    if (node == null) node = vfs.create_file(t);
    const file = node orelse { console.write_str("edit: failed"); return; };
    var content: [4096]u8 = [_]u8{0} ** 4096;
    var clen: usize = if (file.size > 0) vfs.read_file(file, content[0..]) else 0;
    console.write_str("/q=quit /s=save /l=list /dN=del /iN=insert");
    var running = true;
    while (running) {
        console.write_str(">");
        if (kbd.read_line_editor()) |line| {
            if (line.len == 0) continue;
            if (str_eq(line, "/q")) { running = false; }
            else if (str_eq(line, "/s")) { _ = vfs.write_file(file, content[0..clen]); console.write_str("saved"); }
            else if (str_eq(line, "/l")) { list_lines(content[0..clen]); }
            else if (str_starts_with(line, "/d")) { clen = delete_line_c(content[0..], clen, parse_usize(line[2..])); }
            else if (str_starts_with(line, "/i")) { console.write_str("(type line):");
                if (kbd.read_line_editor()) |nl| { clen = append_line_c(content[0..], clen, nl); }
            } else { clen = append_line_c(content[0..], clen, line); }
        }
    }
}
fn list_lines(data: []u8) void {
    var i: usize = 0; var ln: usize = 1;
    while (i < data.len and data[i] != 0) {
        var end = i;
        while (end < data.len and data[end] != 0 and data[end] != '\n') : (end += 1) {}
        if (end > i) { write_num(ln); console.write_str(" "); console.write_str(data[i..end]); }
        ln += 1; i = end + 1;
        if (i < data.len and data[i] == 0) break;
    }
}
fn append_line_c(data: []u8, len: usize, line: []const u8) usize {
    var pos = len; var i: usize = 0;
    while (i < line.len and pos + 1 < data.len) : (i += 1) { data[pos] = line[i]; pos += 1; }
    if (pos < data.len) { data[pos] = '\n'; pos += 1; }
    if (pos < data.len) data[pos] = 0;
    return pos;
}
fn delete_line_c(data: []u8, len: usize, num: usize) usize {
    if (num == 0) return len;
    var i: usize = 0; var ln: usize = 1; var ls: usize = 0;
    while (i < len and data[i] != 0) {
        if (data[i] == '\n') {
            if (ln == num) { const le = i + 1; const rest = len - le; var j: usize = 0; while (j < rest) : (j += 1) data[ls + j] = data[le + j]; data[len - (le - ls)] = 0; return len - (le - ls); }
            ln += 1; ls = i + 1;
        }
        i += 1;
    }
    if (ln == num and i > ls) { data[ls] = 0; return ls; }
    return len;
}
fn write_num(n: usize) void {
    if (n == 0) { console.write_str("0"); return; }
    var buf: [20]u8 = undefined; var i: usize = 0; var v = n;
    while (v > 0) : (v /= 10) { buf[i] = @as(u8, @truncate(v % 10)) + '0'; i += 1; }
    while (i > 0) { i -= 1; console.write_inline(buf[i..i+1]); }
    console.write_str("");
}
fn parse_usize(s: []const u8) usize { var v: usize = 0; for (s) |c| { if (c >= '0' and c <= '9') v = v * 10 + (c - '0'); } return v; }

fn set_ip(args: []const u8) void {
    var parts: [3][]const u8 = undefined; var pi: usize = 0; var start: usize = 0; var i: usize = 0;
    while (i <= args.len and pi < 3) : (i += 1) {
        if (i == args.len or args[i] == ' ') { if (i > start) { parts[pi] = args[start..i]; pi += 1; } start = i + 1; }
    }
    if (pi >= 1) { udp.my_ip = parse_ip4(parts[0]); dhcp.config.ip = udp.my_ip; }
    if (pi >= 2) { udp.gateway_ip = parse_ip4(parts[1]); dhcp.config.gateway = udp.gateway_ip; }
    if (pi >= 3) { udp.dns_ip = parse_ip4(parts[2]); dhcp.config.dns = udp.dns_ip; }
    dhcp.config.configured = true;
    console.write_str("[NET] Static IP configured");
}
fn parse_ip4(s: []const u8) u32 { var ip: u32 = 0; var octet: u32 = 0; for (s) |c| { if (c == '.') { ip = (ip << 8) | octet; octet = 0; } else if (c >= '0' and c <= '9') octet = octet * 10 + (c - '0'); } return (ip << 8) | octet; }

pub fn show_logo() void {
    console.write_str("    ___    _                 ____   _____ ");
    console.write_str("   /   |  (_)___  ____      / __ \\ / ___/ ");
    console.write_str("  / /| | / / __ \\/ __ \\    / / / / \\__ \\  ");
    console.write_str(" / ___ |/ / /_/ / / / /   / /_/ / ___/ /  ");
    console.write_str("/_/  |_/_/\\____/_/ /_/    \\____/ /____/   ");
    console.write_str("");
    console.write_str("   AI SELF-HEALING MICROKERNEL");
    console.write_str("   CPU -> uKernel -> L3 -> AI");
    console.write_str("");
}
pub fn get_prompt() []const u8 { return "aion>"; }

fn set_ai_endpoint(url: []const u8) void { aidaemon.set_config(url, ptr_to_slice(&aidaemon.config.api_key), ptr_to_slice(&aidaemon.config.model)); console.write_str("[AI] Endpoint set"); }
fn set_ai_key(key: []const u8) void { aidaemon.set_config(ptr_to_slice(&aidaemon.config.endpoint), key, ptr_to_slice(&aidaemon.config.model)); console.write_str("[AI] API key set"); }
fn set_ai_model(model: []const u8) void { aidaemon.set_config(ptr_to_slice(&aidaemon.config.endpoint), ptr_to_slice(&aidaemon.config.api_key), model); console.write_str("[AI] Model set"); }
fn ptr_to_slice(ptr: anytype) []const u8 { const p: [*]const u8 = @ptrCast(ptr); var len: usize = 0; while (len < 256 and p[len] != 0) : (len += 1) {} return p[0..len]; }
fn trim(s: []const u8) []const u8 { var start: usize = 0; var end: usize = s.len; while (start < end and s[start] == ' ') : (start += 1) {} while (end > start and s[end - 1] == ' ') : (end -= 1) {} return s[start..end]; }
fn str_eq(a: []const u8, b: []const u8) bool { if (a.len != b.len) return false; for (a, 0..) |c, i| { if (c != b[i]) return false; } return true; }
fn str_starts_with(a: []const u8, prefix: []const u8) bool { if (a.len < prefix.len) return false; for (prefix, 0..) |c, i| { if (c != a[i]) return false; } return true; }
