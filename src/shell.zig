const console = @import("drivers/console.zig");
const wd = @import("core/watchdog.zig");
const dhcp = @import("net/dhcp.zig");
const udp = @import("net/udp.zig");
const aidaemon = @import("ai/daemon.zig");
const l2 = @import("layer2.zig");
const isr = @import("arch/x86_64/isr.zig");

var cwd: []const u8 = "~";
var boot_ticks: u64 = 0;

pub fn process(line: []const u8) bool {
    if (line.len == 0) return true;

    if (str_eq(line, "help")) {
        console.write_str("Aion AI OS  v0.6.0");
        console.write_str("");
        console.write_str("COMMANDS:");
        console.write_str("  help     this message");
        console.write_str("  info     system information");
        console.write_str("  who      about Aion");
        console.write_str("  crash    trigger Layer 3 crash (self-healing)");
        console.write_str("  mem      memory statistics");
        console.write_str("  rebuild  simulate AI kernel rebuild");
        console.write_str("  clear    clear the screen");
        console.write_str("  net      network status");
        console.write_str("  ip       configure static IP");
        console.write_str("  uptime   system uptime");
        console.write_str("  echo     print text");
        console.write_str("  ls       list directory");
        console.write_str("  cd       change directory");
        console.write_str("  ai       AI daemon status / config");
        console.write_str("  logo     show boot logo");
        console.write_str("");
    } else if (str_eq(line, "info")) {
        console.write_str("Aion AI OS -- System Status");
        console.write_str("  Version:  v0.6.0 (TCP + DHCP + AI API)");
        console.write_str("  Layer 3: ");
        if (wd.is_healthy()) {
            console.write_str("    State:   ACTIVE");
        } else {
            console.write_str("    State:   CRASHED");
        }
        console.write_str("  Watchdog: Armed (100Hz timer)");
        if (dhcp.config.configured) {
            console.write_str("  DHCP:     Configured");
        } else {
            console.write_str("  DHCP:     Not configured");
        }
        write_uptime();
    } else if (str_eq(line, "who")) {
        console.write_str("Aion is a self-healing operating system.");
        console.write_str("");
        console.write_str("Architecture:");
        console.write_str("  CPU -> Microkernel -> Layer 3 -> AI Daemon");
        console.write_str("");
        console.write_str("When Layer 3 crashes, the AI daemon contacts");
        console.write_str("an API (OpenAI, Anthropic, OpenCode, etc.) to");
        console.write_str("analyze the crash and generate a fix.");
        console.write_str("Rebuilds happen in under 2 seconds.");
        console.write_str("");
        console.write_str("Open source. Built by anon.");
    } else if (str_eq(line, "crash")) {
        l2.force_crash();
        return false;
    } else if (str_eq(line, "rebuild")) {
        console.write_str("AI REBUILD DEMO:");
        console.write_str("  [1/4] Analyzing crash dump... OK");
        console.write_str("  [2/4] Calling AI API for analysis...");
        console.write_str("  [3/4] Verifying safety constraints... OK");
        console.write_str("  [4/4] Deploying new kernel image... OK");
        console.write_str("Rebuild complete. Layer 3 restarted.");
    } else if (str_eq(line, "mem")) {
        console.write_str("Kernel heap: active (kmalloc/kfree)");
        console.write_str("PMM: bitmap allocator, 4KB page frames");
        console.write_str("VMM: page table management OK");
    } else if (str_eq(line, "clear")) {
        console.clear();
    } else if (str_eq(line, "logo")) {
        show_logo();
    } else if (str_eq(line, "uptime")) {
        write_uptime();
    } else if (str_eq(line, "net")) {
        console.write_str("=== Network Status ===");
        if (dhcp.config.configured) {
            console.write_str("DHCP: Configured");
            console.write_str(" Type 'nettest' to verify connectivity");
        } else {
            console.write_str("DHCP: Not configured");
            console.write_str(" Use 'ip ADDR GATEWAY DNS' for static IP");
            console.write_str(" e.g. 'ip 192.168.1.100 192.168.1.1 8.8.8.8'");
        }
    } else if (str_starts_with(line, "ip ")) {
        set_ip(line[3..]);
    } else if (str_starts_with(line, "echo ")) {
        console.write_str(line[5..]);
    } else if (str_eq(line, "nettest")) {
        test_network();
    } else if (str_eq(line, "tlstest")) {
        test_tls();
    } else if (str_eq(line, "ai")) {
        console.write_str("=== AI Daemon Status ===");
        console.write_str("Mode: API-driven");
        if (aidaemon.config.enabled) {
            console.write_str("API: Configured");
        } else {
            console.write_str("API: Not configured (heuristic fallback)");
            console.write_str("Use 'ai:endpoint URL' 'ai:key KEY' 'ai:model MODEL'");
        }
    } else if (str_starts_with(line, "ai:endpoint ")) {
        set_ai_endpoint(line["ai:endpoint ".len..]);
    } else if (str_starts_with(line, "ai:key ")) {
        set_ai_key(line["ai:key ".len..]);
    } else if (str_starts_with(line, "ai:model ")) {
        set_ai_model(line["ai:model ".len..]);
    } else if (str_eq(line, "ls") or str_eq(line, "dir")) {
        do_ls();
    } else if (str_starts_with(line, "cd ")) {
        do_cd(line[3..]);
    } else if (str_eq(line, "cd")) {
        do_cd("~");
    } else {
        console.write_str("? unknown command. Type 'help'");
    }
    return true;
}

fn set_ip(args: []const u8) void {
    var parts: [3][]const u8 = undefined;
    var pi: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= args.len and pi < 3) : (i += 1) {
        if (i == args.len or args[i] == ' ') {
            if (i > start) {
                parts[pi] = args[start..i];
                pi += 1;
            }
            start = i + 1;
        }
    }
    if (pi >= 1) {
        udp.my_ip = parse_ip4(parts[0]);
        dhcp.config.ip = udp.my_ip;
    }
    if (pi >= 2) {
        udp.gateway_ip = parse_ip4(parts[1]);
        dhcp.config.gateway = udp.gateway_ip;
    }
    if (pi >= 3) {
        udp.dns_ip = parse_ip4(parts[2]);
        dhcp.config.dns = udp.dns_ip;
    }
    dhcp.config.configured = true;
    console.write_str("[NET] Static IP configured");
}

fn parse_ip4(s: []const u8) u32 {
    var ip: u32 = 0;
    var octet: u32 = 0;
    var dots: u8 = 0;
    for (s) |c| {
        if (c == '.') {
            ip = (ip << 8) | octet;
            octet = 0;
            dots += 1;
        } else if (c >= '0' and c <= '9') {
            octet = octet * 10 + (c - '0');
        }
    }
    ip = (ip << 8) | octet;
    return ip;
}

fn write_uptime() void {
    const ticks = isr.get_ticks();
    const secs: u64 = ticks / 100;
    if (secs < 60) {
        console.write_str("  Uptime:   just now");
    } else if (secs < 3600) {
        console.write_str("  Uptime:   a few minutes");
    } else {
        console.write_str("  Uptime:   quite a while");
    }
}

pub fn show_logo() void {
    console.write_str("       █████╗ ██╗ ██████╗ ███╗  ██╗");
    console.write_str("      ██╔══██╗██║██╔═══██╗████╗ ██║");
    console.write_str("      ███████║██║██║   ██║██╔██╗██║");
    console.write_str("      ██╔══██║██║██║   ██║██║╚████║");
    console.write_str("      ██║  ██║██║╚██████╔╝██║ ╚███║");
    console.write_str("      ╚═╝  ╚═╝╚═╝ ╚═════╝ ╚═╝  ╚══╝");
    console.write_str("");
    console.write_str("     AI SELF-HEALING MICROKERNEL  v0.6.0");
    console.write_str("     CPU -> Microkernel -> Layer 3 -> AI");
    console.write_str("");
}

fn do_ls() void {
    if (str_eq(cwd, "~")) {
        console.write_str("kernel/  layer3/  ai/  net/  system/  home/");
    } else if (str_eq(cwd, "/kernel") or str_eq(cwd, "~/kernel")) {
        console.write_str("vmm  pmm  kmalloc  watchdog  task");
    } else if (str_eq(cwd, "/layer3")) {
        console.write_str("shell  daemon  ipc");
    } else if (str_eq(cwd, "/ai")) {
        console.write_str("config  daemon  endpoint  key  model");
    } else if (str_eq(cwd, "/net")) {
        console.write_str("dhcp  tcp  udp  dns  http  tls  arp  e1000");
    } else if (str_eq(cwd, "/system")) {
        console.write_str("version  uptime  log");
    } else if (str_eq(cwd, "/home")) {
        console.write_str("(empty)");
    } else {
        console.write_str("kernel/  layer3/  ai/  net/  system/  home/");
    }
}

fn do_cd(path: []const u8) void {
    const trimmed = trim(path);
    if (trimmed.len == 0 or str_eq(trimmed, "~") or str_eq(trimmed, "/")) {
        cwd = "~";
    } else if (str_eq(trimmed, "kernel") or str_eq(trimmed, "/kernel")) {
        cwd = "/kernel";
    } else if (str_eq(trimmed, "layer3") or str_eq(trimmed, "/layer3")) {
        cwd = "/layer3";
    } else if (str_eq(trimmed, "ai") or str_eq(trimmed, "/ai")) {
        cwd = "/ai";
    } else if (str_eq(trimmed, "net") or str_eq(trimmed, "/net")) {
        cwd = "/net";
    } else if (str_eq(trimmed, "system") or str_eq(trimmed, "/system")) {
        cwd = "/system";
    } else if (str_eq(trimmed, "home") or str_eq(trimmed, "/home")) {
        cwd = "/home";
    } else if (str_eq(trimmed, "..")) {
        cwd = "~";
    } else {
        console.write_str("cd: no such directory");
    }
}

pub fn get_prompt() []const u8 {
    _ = cwd;
    return "~ > ";
}

fn trim(s: []const u8) []const u8 {
    var start: usize = 0;
    var end: usize = s.len;
    while (start < end and s[start] == ' ') : (start += 1) {}
    while (end > start and s[end - 1] == ' ') : (end -= 1) {}
    return s[start..end];
}

pub fn test_tls() void {
    const http = @import("net/http.zig");
    if (!dhcp.config.configured) { console.write_str("[TLS] No IP."); return; }
    console.write_str("[TLS] Testing HTTPS...");
    var resp_buf: [8192]u8 = undefined;
    const empty_body: []const u8 = &[_]u8{};
    if (http.post_json("httpbin.org", 443, "/get", empty_body, resp_buf[0..])) |resp_len| {
        _ = resp_len;
        console.write_str("[TLS] OK");
    } else {
        console.write_str("[TLS] failed");
    }
}

pub fn test_network() void {
    const dns_n = @import("net/dns.zig");
    console.write_str("[TEST] DNS: resolving httpbin.org...");
    if (dns_n.resolve("httpbin.org")) |_ip| {
        _ = _ip;
        console.write_str("[TEST] DNS OK");
    } else {
        console.write_str("[TEST] DNS failed");
    }
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
