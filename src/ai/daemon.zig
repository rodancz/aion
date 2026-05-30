const console = @import("../drivers/console.zig");
const ipc = @import("../ipc/queue.zig");
const http = @import("../net/http.zig");
const wd = @import("../core/watchdog.zig");

pub const RecoveryAction = enum {
    restart_layer3,
    reset_vfs,
    reset_network,
    no_action,
};

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
var api_response: [4096]u8 = [_]u8{0} ** 4096;
var api_response_len: usize = 0;
var selected_action: RecoveryAction = .restart_layer3;

pub fn get_action() RecoveryAction {
    return selected_action;
}

pub fn action_name(action: RecoveryAction) []const u8 {
    return switch (action) {
        .restart_layer3 => "restart_layer3",
        .reset_vfs => "reset_vfs",
        .reset_network => "reset_network",
        .no_action => "no_action",
    };
}

pub fn init(queue: *ipc.Queue) void {
    inbox = queue;
    state = .idle;
    state_ticks = 0;
    crash_data_len = 0;
    selected_action = .restart_layer3;
    console.write_str("[AI] Daemon ready (classification mode)");
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

    parse_endpoint();

    config.enabled = config.hostname[0] != 0;
    if (config.enabled) {
        console.write_str("[AI] API endpoint configured");
    }
}

fn parse_endpoint() void {
    const default_host = "api.openai.com";
    const default_path = "/v1/chat/completions";
    const default_port: u16 = 443;

    var ep_start: usize = 0;
    if (config.endpoint[0] == 'h' and config.endpoint[1] == 't' and config.endpoint[2] == 't' and config.endpoint[3] == 'p') {
        ep_start = if (config.endpoint[4] == 's') @as(usize, 8) else @as(usize, 7);
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
        var j: usize = 0;
        while (j < default_host.len) : (j += 1) { config.hostname[j] = default_host[j]; }
    }
    config.hostname[hi] = 0;

    if (config.endpoint[i] == ':') {
        i += 1;
        var port_val: u16 = 0;
        while (i < config.endpoint.len and config.endpoint[i] >= '0' and config.endpoint[i] <= '9') : (i += 1) {
            port_val = port_val * 10 + (@as(u16, config.endpoint[i]) - '0');
        }
        if (port_val > 0) config.port = port_val;
    } else {
        config.port = default_port;
    }

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

    if (state == .idle) {
        if (ipc.queue_recv(q)) |msg| {
            if (msg.msg_type == ipc.MsgType.crash_report) {
                state = .analyzing;
                state_ticks = 0;
                crash_data_len = 0;
                api_response_len = 0;
                var j: usize = 0;
                while (j < msg.data.len and j < crash_reason.len) : (j += 1) {
                    crash_reason[j] = msg.data[j];
                }
                console.write_str("[AI] Crash report received, analyzing...");
                console.write_str("[AI] Reason: ");
                console.write_str(ptr_to_slice(&crash_reason));
            }
        }
        return;
    }

    if (state == .analyzing) {
        state_ticks += 1;
        if (state_ticks == 1) {
            // Classify locally first (fast path)
            selected_action = classify_local();
            if (config.enabled) {
                state = .calling_api;
                state_ticks = 0;
                crash_data_len = build_classify_json();
                console.write_str("[AI] Local: ");
                console.write_str(action_name(selected_action));
                console.write_str("[AI] Calling API for classification...");
            } else {
                console.write_str("[AI] No API configured — local: ");
                console.write_str(action_name(selected_action));
                state = .deploying;
                state_ticks = 0;
            }
        }
        return;
    }

    if (state == .calling_api) {
        state_ticks += 1;
        if (state_ticks == 1) {
            const path = ptr_to_slice(&config.path);
            const body = crash_data[0..crash_data_len];
            if (http.post_json(ptr_to_slice(&config.hostname), config.port, path, body, api_response[0..])) |resp_len| {
                api_response_len = resp_len;
                console.write_str("[AI] API response received — parsing classification...");
                const api_action = parse_api_classification();
                if (api_action) |action| {
                    selected_action = action;
                    console.write_str("[AI] API classified as: ");
                    console.write_str(action_name(action));
                } else {
                    console.write_str("[AI] API classification failed — using local: ");
                    console.write_str(action_name(selected_action));
                }
            } else {
                console.write_str("[AI] API call failed — using local: ");
                console.write_str(action_name(selected_action));
            }
            state = .deploying;
            state_ticks = 0;
        }
        return;
    }

    if (state == .deploying) {
        state_ticks += 1;
        if (state_ticks == 3) {
            console.write_str("[AI] Executing recovery: ");
            console.write_str(action_name(selected_action));
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

fn classify_local() RecoveryAction {
    const reason = ptr_to_slice(&crash_reason);

    if (contains(reason, "vfs")) return .reset_vfs;
    if (contains(reason, "filesystem")) return .reset_vfs;
    if (contains(reason, "ramfs")) return .reset_vfs;
    if (contains(reason, "network")) return .reset_network;
    if (contains(reason, "tcp")) return .reset_network;
    if (contains(reason, "nic")) return .reset_network;
    if (contains(reason, "e1000")) return .reset_network;

    return .restart_layer3;
}

fn parse_api_classification() ?RecoveryAction {
    const resp = api_response[0..api_response_len];

    if (contains(resp, "restart_layer3") or contains(resp, "restart layer3") or contains(resp, "restart layer 3")) return .restart_layer3;
    if (contains(resp, "reset_vfs") or contains(resp, "reset vfs") or contains(resp, "reset filesystem")) return .reset_vfs;
    if (contains(resp, "reset_network") or contains(resp, "reset network") or contains(resp, "reset networking")) return .reset_network;
    if (contains(resp, "no_action") or contains(resp, "no action") or contains(resp, "ignore")) return .no_action;

    return null;
}

fn contains(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            const hc = haystack[i + j];
            const nc = needle[j];
            if (hc != nc and (hc | 0x20) != (nc | 0x20)) { matched = false; break; }
        }
        if (matched) return true;
    }
    return false;
}

fn build_classify_json() usize {
    var buf: [2048]u8 = undefined;
    var i: usize = 0;

    const prefix = "{\"model\":\"";
    for (prefix) |c| { buf[i] = c; i += 1; }
    const model = ptr_to_slice(&config.model);
    for (model) |c| { buf[i] = c; i += 1; }
    const mid = "\",\"messages\":[{\"role\":\"user\",\"content\":\"An OS kernel Layer 3 crashed. Reason: ";
    for (mid) |c| { buf[i] = c; i += 1; }
    const reason = ptr_to_slice(&crash_reason);
    for (reason) |c| { buf[i] = c; i += 1; }
    const suffix = ". Classify this crash into ONE recovery action from this list: restart_layer3, reset_vfs, reset_network, no_action. Reply with ONLY the action name, nothing else.\"}]}";
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
