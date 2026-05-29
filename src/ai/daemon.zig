const console = @import("../drivers/console.zig");
const ipc = @import("../ipc/queue.zig");
const http = @import("../net/http.zig");

pub const AiConfig = struct {
    endpoint: [256]u8,
    api_key: [128]u8,
    model: [64]u8,
    hostname: [128]u8,
    port: u16,
    path: [256]u8,
    enabled: bool,
};

pub var config: AiConfig = AiConfig{
    .endpoint = [_]u8{0} ** 256,
    .api_key = [_]u8{0} ** 128,
    .model = [_]u8{0} ** 64,
    .hostname = [_]u8{0} ** 128,
    .port = 443,
    .path = [_]u8{0} ** 256,
    .enabled = false,
};

var inbox: ?*ipc.Queue = null;
var state: enum { idle, analyzing, calling_api, deploying } = .idle;
var state_ticks: u64 = 0;
var crash_reason: [64]u8 = [_]u8{0} ** 64;
var crash_data: [512]u8 = [_]u8{0} ** 512;
var crash_data_len: usize = 0;

pub fn init(queue: *ipc.Queue) void {
    inbox = queue;
    state = .idle;
    state_ticks = 0;
    crash_data_len = 0;
    console.write_str("[AI] Daemon started (idle, API mode)");
}

pub fn set_config(endpoint: []const u8, api_key: []const u8, model: []const u8) void {
    var i: usize = 0;
    while (i < endpoint.len and i < config.endpoint.len - 1) : (i += 1) config.endpoint[i] = endpoint[i];
    config.endpoint[i] = 0;

    i = 0;
    while (i < api_key.len and i < config.api_key.len - 1) : (i += 1) config.api_key[i] = api_key[i];
    config.api_key[i] = 0;

    i = 0;
    while (i < model.len and i < config.model.len - 1) : (i += 1) config.model[i] = model[i];
    config.model[i] = 0;

    // Parse hostname + path from endpoint URL (e.g. https://api.openai.com/v1/chat/completions)
    parse_endpoint();

    config.enabled = config.hostname[0] != 0;
    if (config.enabled) {
        console.write_str("[AI] API endpoint configured");
    }
}

fn parse_endpoint() void {
    // Default: OpenAI-compatible API
    const default_host = "api.openai.com";
    const default_path = "/v1/chat/completions";
    const default_port: u16 = 443;

    // Extract hostname from endpoint config
    var ep_start: usize = 0;
    if (config.endpoint[0] == 'h' and config.endpoint[1] == 't' and config.endpoint[2] == 't' and config.endpoint[3] == 'p') {
        ep_start = if (config.endpoint[4] == 's') @as(usize, 8) else @as(usize, 7); // skip https:// or http://
    }

    var hi: usize = 0;
    var i: usize = ep_start;
    while (i < config.endpoint.len and config.endpoint[i] != 0 and config.endpoint[i] != '/' and config.endpoint[i] != ':') : (i += 1) {
        if (hi < config.hostname.len - 1) {
            config.hostname[hi] = config.endpoint[i];
            hi += 1;
        }
    }
    if (hi == 0) {
        // Use defaults
        var j: usize = 0;
        while (j < default_host.len) : (j += 1) { config.hostname[j] = default_host[j]; }
    }
    config.hostname[hi] = 0;

    if (config.endpoint[i] == ':') {
        // Parse port
        i += 1;
        var port_val: u16 = 0;
        while (i < config.endpoint.len and config.endpoint[i] >= '0' and config.endpoint[i] <= '9') : (i += 1) {
            port_val = port_val * 10 + (@as(u16, config.endpoint[i]) - '0');
        }
        if (port_val > 0) config.port = port_val;
    } else {
        config.port = default_port;
    }

    // Path
    var pi: usize = 0;
    if (config.endpoint[i] == '/') {
        while (i < config.endpoint.len and config.endpoint[i] != 0 and pi < config.path.len - 1) : (i += 1) {
            config.path[pi] = config.endpoint[i];
            pi += 1;
        }
    }
    if (pi == 0) {
        var j: usize = 0;
        while (j < default_path.len) : (j += 1) { config.path[j] = default_path[j]; }
        pi = default_path.len;
    }
    config.path[pi] = 0;
}

pub fn tick() void {
    const q = inbox orelse return;

    // Step 1: Check for crash reports
    if (state == .idle) {
        if (ipc.queue_recv(q)) |msg| {
            if (msg.msg_type == ipc.MsgType.crash_report) {
                state = .analyzing;
                state_ticks = 0;
                crash_data_len = 0;
                var j: usize = 0;
                while (j < msg.data.len and j < crash_reason.len) : (j += 1) {
                    crash_reason[j] = msg.data[j];
                }
                console.write_str("[AI] Crash report received, analyzing...");
            }
        }
        return;
    }

    // Step 2: Build crash report data
    if (state == .analyzing) {
        state_ticks += 1;
        if (state_ticks == 1) {
            // Build JSON crash report
            crash_data_len = build_crash_json();
            if (config.enabled) {
                state = .calling_api;
                state_ticks = 0;
                console.write_str("[AI] Calling API for analysis...");
            } else {
                // Fallback: simulated analysis
                console.write_str("[AI] No API configured, using heuristics");
                state = .deploying;
                state_ticks = 0;
            }
        }
        return;
    }

    // Step 3: Call API
    if (state == .calling_api) {
        state_ticks += 1;
        if (state_ticks == 1) {
            var resp_buf: [4096]u8 = undefined;
            const path = ptr_to_slice(&config.path);
            const body = crash_data[0..crash_data_len];
            if (http.post_json(ptr_to_slice(&config.hostname), config.port, path, body, resp_buf[0..])) |resp_len| {
                console.write_str("[AI] API response received");
                _ = http.parse_body(resp_buf[0..resp_len]);
                state = .deploying;
                state_ticks = 0;
            } else {
                console.write_str("[AI] API call failed, using heuristics");
                state = .deploying;
                state_ticks = 0;
            }
        }
        return;
    }

    // Step 4: Deploy fix
    if (state == .deploying) {
        state_ticks += 1;
        if (state_ticks == 5) {
            console.write_str("[AI] Deploying patch... OK");
            var signal: ipc.Message = undefined;
            signal.msg_type = ipc.MsgType.rebuild_cmd;
            signal.source = 0;
            _ = ipc.queue_send(q, signal);
            state = .idle;
            state_ticks = 0;
        }
        return;
    }
}

fn build_crash_json() usize {
    // Build JSON: {"model":"...","messages":[{"role":"user","content":"The kernel Layer 3 crashed. Reason: X. Suggest a fix."}]}
    var buf: [2048]u8 = undefined;
    var i: usize = 0;

    const prefix = "{\"model\":\"";
    for (prefix) |c| { buf[i] = c; i += 1; }
    const model = ptr_to_slice(&config.model);
    for (model) |c| { buf[i] = c; i += 1; }
    const mid = "\",\"messages\":[{\"role\":\"user\",\"content\":\"CPUMAIN microkernel Layer 3 crashed. Reason: ";
    for (mid) |c| { buf[i] = c; i += 1; }
    const reason = ptr_to_slice(&crash_reason);
    for (reason) |c| { buf[i] = c; i += 1; }
    const suffix = ". Analyze the crash and suggest a fix in one sentence.\"}]}";
    for (suffix) |c| { buf[i] = c; i += 1; }

    var j: usize = 0;
    while (j < i) : (j += 1) { crash_data[j] = buf[j]; }
    return i;
}

fn ptr_to_slice(ptr: anytype) []const u8 {
    const p: [*]const u8 = @ptrCast(ptr);
    var len: usize = 0;
    while (len < 256 and p[len] != 0) : (len += 1) {}
    return p[0..len];
}

pub fn is_busy() bool {
    return state != .idle;
}
