const tcp = @import("../net/tcp.zig");
const dns = @import("../net/dns.zig");
const sha256 = @import("../crypto/sha256.zig");
const aes = @import("../crypto/aes.zig");
const bigint = @import("../crypto/bigint.zig");
const console = @import("../drivers/console.zig");

const TLS_VERSION: u16 = 0x0303; // TLS 1.2

var client_random: [32]u8 = [_]u8{0} ** 32;
var server_random: [32]u8 = [_]u8{0} ** 32;
var master_secret: [48]u8 = [_]u8{0} ** 48;
var client_write_key: [16]u8 = [_]u8{0} ** 16;
var server_write_key: [16]u8 = [_]u8{0} ** 16;
var client_write_iv: [16]u8 = [_]u8{0} ** 16;
var server_write_iv: [16]u8 = [_]u8{0} ** 16;
var client_round_keys: [44]u32 = [_]u32{0} ** 44;
var server_round_keys: [44]u32 = [_]u32{0} ** 44;
var client_seq: u64 = 0;
var server_seq: u64 = 0;
var handshake_encrypted: bool = false;

pub fn tls_connect(hostname: []const u8, port: u16) ?*tcp.TcpConn {
    console.write_str("[TLS] Connecting...");

    const ip = dns.resolve(hostname) orelse {
        console.write_str("[TLS] DNS failed");
        return null;
    };

    const conn = tcp.connect(ip, port, @truncate(49152 + @import("../arch/x86_64/isr.zig").get_ticks() % 16384)) orelse {
        console.write_str("[TLS] TCP connect failed");
        return null;
    };

    // Wait for TCP connection
    var ticks: u64 = 0;
    while (!tcp.is_established(conn) and ticks < 500) : (ticks += 1) {
        process_net();
        tcp.tick();
        spin(100000);
    }
    if (!tcp.is_established(conn)) {
        console.write_str("[TLS] TCP handshake timeout");
        return null;
    }

    // Generate client random
    const timer = @import("../arch/x86_64/isr.zig").get_ticks();
    fill_random(&client_random, timer);
    fill_random(&server_random, 0); // will be filled from server response

    // Send ClientHello
    send_client_hello(conn, hostname);

    // Read ServerHello + Certificate + ServerHelloDone
    var buf: [8192]u8 = undefined;
    var total: usize = 0;
    ticks = 0;
    while (ticks < 1000) : (ticks += 1) {
        process_net();
        tcp.tick();
        if (tcp.recv(conn, buf[total..])) |n| {
            total += n;
            if (parse_server_messages(buf[0..total], conn)) break;
        }
        spin(50000);
    }

    if (ticks >= 1000) {
        console.write_str("[TLS] Handshake timeout");
        return null;
    }

    console.write_str("[TLS] Handshake complete");
    return conn;
}

pub fn tls_send(conn: *tcp.TcpConn, data: []const u8) bool {
    if (!handshake_encrypted) return false;

    var record_buf: [2048]u8 = undefined;

    record_buf[0] = 0x17; // Application Data
    record_buf[1] = @truncate(TLS_VERSION >> 8);
    record_buf[2] = @truncate(TLS_VERSION);

    // Encrypted data goes after the 5-byte header + 16-byte explicit IV
    const data_start: usize = 5 + 16;

    // Encrypt: data + MAC + padding
    var plaintext: [2048]u8 = undefined;
    var pi: usize = 0;
    var di: usize = 0;
    while (di < data.len) : (di += 1) { plaintext[pi] = data[di]; pi += 1; }

    // MAC (HMAC-SHA256 with sequence number)
    var mac: [32]u8 = undefined;
    var mac_input: [13]u8 = undefined;
    mac_input[0] = @truncate(client_seq >> 56);
    mac_input[1] = @truncate(client_seq >> 48);
    mac_input[2] = @truncate(client_seq >> 40);
    mac_input[3] = @truncate(client_seq >> 32);
    mac_input[4] = @truncate(client_seq >> 24);
    mac_input[5] = @truncate(client_seq >> 16);
    mac_input[6] = @truncate(client_seq >> 8);
    mac_input[7] = @truncate(client_seq);
    mac_input[8] = 0x17;
    mac_input[9] = @truncate(TLS_VERSION >> 8);
    mac_input[10] = @truncate(TLS_VERSION);
    mac_input[11] = @truncate(pi >> 8);
    mac_input[12] = @truncate(pi);

    sha256.hmac_sha256(client_write_key[0..], mac_input[0..], mac[0..]);
    // Actually MAC should cover sequence + header + data

    var mac_ctx = sha256.Sha256.init();
    mac_ctx.update(mac_input[0..]);
    mac_ctx.update(plaintext[0..pi]);
    mac_ctx.finalize(mac[0..]);

    var mj: usize = 0;
    while (mj < 32) : (mj += 1) { plaintext[pi] = mac[mj]; pi += 1; }

    // CBC padding
    const pad_len: u8 = @truncate(16 - (pi % 16));
    var pd: u8 = 0;
    while (pd < pad_len) : (pd += 1) { plaintext[pi] = pad_len - 1; pi += 1; }

    // Generate IV and encrypt
    var iv: [16]u8 = gen_iv();
    aes.cbc_encrypt(plaintext[0..pi], record_buf[data_start..], iv[0..], client_round_keys[0..]);

    // Copy IV right after record header (positions 5..20)
    var ivj: usize = 0;
    while (ivj < 16) : (ivj += 1) { record_buf[5 + ivj] = iv[ivj]; }

    const total_len = 16 + pi;
    record_buf[3] = @truncate(total_len >> 8);
    record_buf[4] = @truncate(total_len);

    client_seq += 1;
    return tcp.send(conn, record_buf[0 .. data_start + pi]);
}

pub fn tls_recv(conn: *tcp.TcpConn, buf: []u8) ?usize {
    if (!handshake_encrypted) return null;
    return tcp.recv(conn, buf); // Simple passthrough for now; full decryption in tls_read_record
}

fn send_client_hello(conn: *tcp.TcpConn, hostname: []const u8) void {
    var buf: [2048]u8 = [_]u8{0} ** 2048;
    var i: usize = 0;

    // TLS record header
    buf[i] = 0x16; i += 1; // Handshake
    buf[i] = @truncate(TLS_VERSION >> 8); i += 1;
    buf[i] = @truncate(TLS_VERSION); i += 1;
    // Length placeholder at i+0, i+1
    const len_pos = i;
    i += 2;

    // Handshake: ClientHello
    buf[i] = 0x01; i += 1; // type
    // 3-byte length placeholder
    const ch_len_pos = i;
    i += 3;

    // Version
    buf[i] = @truncate(TLS_VERSION >> 8); i += 1;
    buf[i] = @truncate(TLS_VERSION); i += 1;

    // Client random
    var rj: usize = 0;
    while (rj < 32) : (rj += 1) { buf[i] = client_random[rj]; i += 1; }

    // Session ID (empty)
    buf[i] = 0; i += 1;

    // Cipher suites: TLS_RSA_WITH_AES_128_CBC_SHA256 (0x003C) + TLS_RSA_WITH_AES_128_CBC_SHA (0x002F)
    buf[i] = 0; i += 1; // length high
    buf[i] = 4; i += 1; // 2 suites = 4 bytes
    buf[i] = 0x00; i += 1; buf[i] = 0x3C; i += 1; // TLS_RSA_WITH_AES_128_CBC_SHA256
    buf[i] = 0x00; i += 1; buf[i] = 0x2F; i += 1; // TLS_RSA_WITH_AES_128_CBC_SHA (fallback)

    // Compression methods: null
    buf[i] = 1; i += 1; // length
    buf[i] = 0; i += 1; // null

    // Extensions
    const ext_start = i;
    i += 2; // total extensions length placeholder

    // SNI extension
    buf[i] = 0x00; i += 1; buf[i] = 0x00; i += 1; // server_name type=0
    const sni_len_pos = i; i += 2;
    // ServerNameList
    const snl_len_pos = i; i += 2;
    buf[i] = 0; i += 1; // name_type = hostname
    buf[i] = @truncate(hostname.len >> 8); i += 1;
    buf[i] = @truncate(hostname.len); i += 1;
    var hj: usize = 0;
    while (hj < hostname.len) : (hj += 1) { buf[i] = hostname[hj]; i += 1; }

    const snl_len = i - snl_len_pos - 2;
    buf[snl_len_pos] = @truncate(snl_len >> 8);
    buf[snl_len_pos + 1] = @truncate(snl_len);
    const sni_len = i - sni_len_pos - 2;
    buf[sni_len_pos] = @truncate(sni_len >> 8);
    buf[sni_len_pos + 1] = @truncate(sni_len);

    const ext_len = i - ext_start - 2;
    buf[ext_start] = @truncate(ext_len >> 8);
    buf[ext_start + 1] = @truncate(ext_len);

    // Fix lengths
    const ch_len = i - ch_len_pos - 3;
    buf[ch_len_pos] = @truncate(ch_len >> 16);
    buf[ch_len_pos + 1] = @truncate(ch_len >> 8);
    buf[ch_len_pos + 2] = @truncate(ch_len);

    const record_payload = i - len_pos - 2;
    buf[len_pos] = @truncate(record_payload >> 8);
    buf[len_pos + 1] = @truncate(record_payload);

    _ = tcp.send(conn, buf[0..i]);
}

fn parse_server_messages(data: []const u8, conn: *tcp.TcpConn) bool {
    var offset: usize = 0;
    var got_server_hello: bool = false;
    var got_certificate: bool = false;
    var got_server_done: bool = false;
    var cert_data: [4096]u8 = undefined;
    var cert_len: usize = 0;

    while (offset + 5 <= data.len) {
        const rec_type = data[offset];
        const rec_ver = (@as(u16, data[offset + 1]) << 8) | data[offset + 2];
        const rec_len = (@as(u16, data[offset + 3]) << 8) | data[offset + 4];
        if (offset + 5 + rec_len > data.len) break;

        if (rec_type == 0x16 and rec_ver >= 0x0301) { // Handshake
            var ho: usize = offset + 5;
            const end = ho + rec_len;
            while (ho + 4 <= end) {
                const htype = data[ho];
                const hlen = (@as(u32, data[ho + 1]) << 16) | (@as(u32, data[ho + 2]) << 8) | data[ho + 3];
                if (ho + 4 + hlen > end) break;

                switch (htype) {
                    2 => { // ServerHello
                        // Copy server random
                        if (hlen >= 38) {
                            var j: usize = 0;
                            while (j < 32) : (j += 1) server_random[j] = data[ho + 4 + 6 + j];
                        }
                        got_server_hello = true;
                    },
                    11 => { // Certificate
                        // Parse to extract public key
                        cert_len = hlen;
                        if (hlen > cert_data.len) {
                            cert_len = cert_data.len;
                        }
                        var cj: usize = 0;
                        while (cj < cert_len and cj < hlen) : (cj += 1) cert_data[cj] = data[ho + 4 + cj];
                        got_certificate = true;
                    },
                    14 => { // ServerHelloDone
                        got_server_done = true;
                    },
                    else => {},
                }
                ho += 4 + hlen;
            }
        }

        offset += 5 + rec_len;
    }

    if (got_server_hello and got_certificate and got_server_done) {
        // Extract public key and complete handshake
        const result = complete_handshake(conn, cert_data[0..cert_len]);
        return result;
    }

    return false;
}

fn complete_handshake(conn: *tcp.TcpConn, cert_raw: []const u8) bool {
    // Extract RSA public key from certificate
    // Certificate is ASN.1 DER encoded
    // Skip outer SEQUENCE, skip tbsCertificate, find subjectPublicKeyInfo
    var mod: [256]u8 = [_]u8{0} ** 256;
    var mod_len: usize = 0;
    var exp: [3]u8 = [_]u8{0} ** 3;
    var exp_val: u32 = 0;

    if (!parse_cert_pubkey(cert_raw, &mod, &mod_len, &exp, &exp_val)) {
        console.write_str("[TLS] Certificate parsing failed");
        return false;
    }

    // Generate premaster secret (48 bytes)
    var premaster: [48]u8 = undefined;
    premaster[0] = @truncate(TLS_VERSION >> 8);
    premaster[1] = @truncate(TLS_VERSION);
    var pi: usize = 2;
    const timer = @import("../arch/x86_64/isr.zig").get_ticks();
    var rnd: u64 = timer;
    while (pi < 48) : (pi += 1) {
        rnd = rnd *% 1103515245 +% 12345;
        premaster[pi] = @truncate(rnd & 0xFF);
    }

    // RSA encrypt premaster with server's public key
    var encrypted_premaster: [256]u8 = [_]u8{0} ** 256;
    var enc_len: usize = 0;
    if (!rsa_encrypt(&premaster, &mod, mod_len, exp_val, &encrypted_premaster, &enc_len)) {
        console.write_str("[TLS] RSA encryption failed");
        return false;
    }

    // Send ClientKeyExchange
    send_client_key_exchange(conn, encrypted_premaster[0..enc_len]);

    // Compute master secret
    compute_keys(&premaster);

    // Send ChangeCipherSpec
    var ccs: [6]u8 = [_]u8{ 0x14, @truncate(TLS_VERSION >> 8), @truncate(TLS_VERSION), 0, 1, 1 };
    handshake_encrypted = true;
    _ = tcp.send(conn, ccs[0..]);

    // Send Finished (encrypted)
    send_finished(conn);

    handshake_encrypted = true;
    return true;
}

fn compute_keys(premaster: []const u8) void {
    // Master secret = PRF(premaster, "master secret", client_random || server_random)
    var seed: [64]u8 = undefined;
    var si: usize = 0;
    var j: usize = 0;
    while (j < 32) : (j += 1) { seed[si] = client_random[j]; si += 1; }
    j = 0;
    while (j < 32) : (j += 1) { seed[si] = server_random[j]; si += 1; }

    sha256.tls_prf_sha256(premaster, "master secret", seed[0..si], master_secret[0..]);

    // Key block = PRF(master, "key expansion", server_random || client_random)
    si = 0;
    j = 0;
    while (j < 32) : (j += 1) { seed[si] = server_random[j]; si += 1; }
    j = 0;
    while (j < 32) : (j += 1) { seed[si] = client_random[j]; si += 1; }

    var key_block: [128]u8 = undefined;
    sha256.tls_prf_sha256(master_secret[0..], "key expansion", seed[0..si], key_block[0..]);

    // client_write_key (16) + server_write_key (16) + client_write_IV (16) + server_write_IV (16)
    var ki: usize = 0;
    j = 0;
    while (j < 16) : (j += 1) { client_write_key[j] = key_block[ki]; ki += 1; }
    j = 0;
    while (j < 16) : (j += 1) { server_write_key[j] = key_block[ki]; ki += 1; }
    j = 0;
    while (j < 16) : (j += 1) { client_write_iv[j] = key_block[ki]; ki += 1; }
    j = 0;
    while (j < 16) : (j += 1) { server_write_iv[j] = key_block[ki]; ki += 1; }

    aes.key_expand_128(client_write_key[0..], client_round_keys[0..]);
    aes.key_expand_128(server_write_key[0..], server_round_keys[0..]);
}

fn send_client_key_exchange(conn: *tcp.TcpConn, encrypted: []const u8) void {
    var buf: [1024]u8 = [_]u8{0} ** 1024;
    var i: usize = 0;
    buf[i] = 0x16; i += 1;
    buf[i] = @truncate(TLS_VERSION >> 8); i += 1;
    buf[i] = @truncate(TLS_VERSION); i += 1;

    const len_pos = i; i += 2;

    buf[i] = 0x10; i += 1; // ClientKeyExchange type
    const cke_len = 4 + encrypted.len;
    buf[i] = @truncate(cke_len >> 16); i += 1;
    buf[i] = @truncate(cke_len >> 8); i += 1;
    buf[i] = @truncate(cke_len); i += 1;

    // Encrypted premaster length
    buf[i] = @truncate(encrypted.len >> 8); i += 1;
    buf[i] = @truncate(encrypted.len); i += 1;

    var ej: usize = 0;
    while (ej < encrypted.len) : (ej += 1) { buf[i] = encrypted[ej]; i += 1; }

    const plen = i - len_pos - 2;
    buf[len_pos] = @truncate(plen >> 8);
    buf[len_pos + 1] = @truncate(plen);

    _ = tcp.send(conn, buf[0..i]);
}

fn send_finished(conn: *tcp.TcpConn) void {
    // Verify data = PRF(master, "client finished", SHA256(handshake_messages))
    var verify: [12]u8 = undefined;
    var handshake_hash: [32]u8 = undefined;
    // Simplified: use empty hash for initial test
    var hash_ctx = sha256.Sha256.init();
    hash_ctx.update("handshake");
    hash_ctx.finalize(handshake_hash[0..]);

    sha256.tls_prf_sha256(master_secret[0..], "client finished", handshake_hash[0..], verify[0..12]);

    // Build Finished message (handshake type 0x14)
    var buf: [256]u8 = [_]u8{0} ** 256;
    var i: usize = 0;
    buf[i] = 0x16; i += 1;
    buf[i] = @truncate(TLS_VERSION >> 8); i += 1;
    buf[i] = @truncate(TLS_VERSION); i += 1;

    // Encrypted record
    var plaintext: [64]u8 = undefined;
    var pi: usize = 0;
    plaintext[pi] = 0x14; pi += 1; // Finished
    plaintext[pi] = 0; pi += 1; plaintext[pi] = 0; pi += 1; plaintext[pi] = 12; pi += 1; // length
    var vj: usize = 0;
    while (vj < 12) : (vj += 1) { plaintext[pi] = verify[vj]; pi += 1; }

    // MAC
    var mac: [32]u8 = undefined;
    var mac_input: [13]u8 = undefined;
    mac_input[0] = @truncate(client_seq >> 56);
    mac_input[1] = @truncate(client_seq >> 48);
    mac_input[2] = @truncate(client_seq >> 40);
    mac_input[3] = @truncate(client_seq >> 32);
    mac_input[4] = @truncate(client_seq >> 24);
    mac_input[5] = @truncate(client_seq >> 16);
    mac_input[6] = @truncate(client_seq >> 8);
    mac_input[7] = @truncate(client_seq);
    mac_input[8] = 0x16; mac_input[9] = @truncate(TLS_VERSION >> 8); mac_input[10] = @truncate(TLS_VERSION);
    mac_input[11] = @truncate(pi >> 8); mac_input[12] = @truncate(pi);

    var mac_ctx = sha256.Sha256.init();
    mac_ctx.update(mac_input[0..]);
    mac_ctx.update(plaintext[0..pi]);
    mac_ctx.finalize(mac[0..]);
    var mj: usize = 0;
    while (mj < 32) : (mj += 1) { plaintext[pi] = mac[mj]; pi += 1; }

    // Padding
    const pad_len: u8 = @truncate(16 - (pi % 16));
    var pd: u8 = 0;
    while (pd < pad_len) : (pd += 1) { plaintext[pi] = pad_len - 1; pi += 1; }

    // CBC encrypt + build record
    var iv: [16]u8 = gen_iv();
    const enc_start: usize = 5 + 16;
    var oi: usize = enc_start;
    while (oi < enc_start + pi) : (oi += 1) buf[oi] = 0;
    aes.cbc_encrypt(plaintext[0..pi], buf[enc_start..], iv[0..], client_round_keys[0..]);

    const real_total = 5 + 16 + pi;
    buf[3] = @truncate((16 + pi) >> 8);
    buf[4] = @truncate(16 + pi);
    var ivj: usize = 0;
    while (ivj < 16) : (ivj += 1) buf[5 + ivj] = iv[ivj];

    client_seq += 1;
    _ = tcp.send(conn, buf[0..real_total]);
}

fn parse_cert_pubkey(cert: []const u8, mod: []u8, mod_len: *usize, exp: []u8, exp_val: *u32) bool {
    // Minimal X.509 DER parsing: find RSA public key (modulus + exponent)
    // Certificate structure: SEQUENCE { SEQUENCE { ... }, SEQUENCE { OID, NULL }, BIT STRING }
    // The BIT STRING contains: SEQUENCE { INTEGER modulus, INTEGER exponent }
    // We skip to the BIT STRING and parse its contents

    if (cert.len < 4) return false;
    if (cert[0] != 0x30) return false; // SEQUENCE

    var pos: usize = 2;
    _ = if (cert[1] < 0x80) @as(usize, cert[1]) else blk: {
        const num_len = cert[1] & 0x7F;
        var l: usize = 0;
        var nl: usize = 0;
        while (nl < num_len) : (nl += 1) l = (l << 8) | cert[pos + nl];
        pos += num_len;
        break :blk l;
    };

    // Skip to BIT STRING containing pubkey
    // Search for BIT STRING (0x03) near the end
    var search: usize = pos;
    while (search < cert.len - 10) : (search += 1) {
        if (cert[search] == 0x03) { // BIT STRING
            var bs_pos = search + 1;
            _ = if (cert[bs_pos] < 0x80) @as(usize, cert[bs_pos]) else blk2: {
                const nl = cert[bs_pos] & 0x7F;
                var l: usize = 0;
                var n: usize = 0;
                while (n < nl) : (n += 1) l = (l << 8) | cert[bs_pos + 1 + n];
                bs_pos += nl;
                break :blk2 l;
            };
            bs_pos += 1;
            // Skip unused bits byte
            bs_pos += 1;

            // Now we have SEQUENCE { INTEGER mod, INTEGER exp }
            if (cert[bs_pos] != 0x30) continue; // Not SEQUENCE
            bs_pos += 1;
            _ = cert[bs_pos]; // inner length (skip)
            bs_pos += 1;
            if (bs_pos >= cert.len) continue;

            // First INTEGER (modulus)
            if (cert[bs_pos] != 0x02) continue;
            bs_pos += 1;
            const mod_int_len = if (cert[bs_pos] < 0x80) @as(usize, cert[bs_pos]) else blk3: {
                const nl = cert[bs_pos] & 0x7F;
                var l: usize = 0;
                var n: usize = 0;
                while (n < nl) : (n += 1) l = (l << 8) | cert[bs_pos + 1 + n];
                bs_pos += nl;
                break :blk3 l;
            };
            bs_pos += 1;

            if (mod_int_len > 1 and cert[bs_pos] == 0) {
                // Skip leading zero
                bs_pos += 1;
                mod_len.* = mod_int_len - 1;
            } else {
                mod_len.* = mod_int_len;
            }
            if (mod_len.* > mod.len) mod_len.* = mod.len;
            var mj: usize = 0;
            while (mj < mod_len.*) : (mj += 1) mod[mj] = cert[bs_pos + mj];
            bs_pos += mod_int_len;

            // Second INTEGER (exponent)
            if (cert[bs_pos] != 0x02) continue;
            bs_pos += 1;
            const exp_int_len = cert[bs_pos];
            bs_pos += 1;

            exp_val.* = 0;
            var ej: usize = 0;
            while (ej < exp_int_len and ej < 3) : (ej += 1) {
                exp_val.* = (exp_val.* << 8) | cert[bs_pos + ej];
                if (ej < exp.len) exp[ej] = cert[bs_pos + ej];
            }

            return true;
        }
    }
    return false;
}

fn rsa_encrypt(data: []const u8, mod: []const u8, mod_len: usize, exp_val: u32, out: []u8, out_len: *usize) bool {
    // PKCS#1 v1.5 padding: 0x00 || 0x02 || random (non-zero) || 0x00 || data
    const k = mod_len; // key size in bytes
    if (k < data.len + 11) return false;

    var padded: [256]u8 = [_]u8{0} ** 256;
    padded[0] = 0x00;
    padded[1] = 0x02;
    var pi: usize = 2;
    var rng: u64 = @import("../arch/x86_64/isr.zig").get_ticks();
    while (pi < k - data.len - 1) : (pi += 1) {
        rng = rng *% 1103515245 +% 12345;
        var b: u8 = @truncate(rng & 0xFF);
        if (b == 0) b = 1;
        padded[pi] = b;
    }
    padded[pi] = 0x00; pi += 1;
    var di: usize = 0;
    while (di < data.len) : (di += 1) { padded[pi] = data[di]; pi += 1; }

    // Convert message to bigint
    var msg_bn = bigint.BigInt.from_bytes_be(padded[0..k]);

    // Convert modulus to bigint
    var mod_bn = bigint.BigInt.from_bytes_be(mod[0..mod_len]);

    // Convert exponent to bigint
    var exp_bn = bigint.BigInt.from_u64(exp_val);

    // Compute ciphertext = msg^exp mod n
    var ct_bn = bigint.BigInt.modpow(&msg_bn, &exp_bn, &mod_bn);

    // Convert back to bytes
    ct_bn.to_bytes_be(out);
    out_len.* = k;
    return true;
}

fn fill_random(buf: []u8, seed: u64) void {
    var rng = seed;
    if (rng == 0) rng = 0xCAFEBABE;
    var i: usize = 0;
    while (i < buf.len) : (i += 1) {
        rng = rng *% 1103515245 +% 12345;
        buf[i] = @as(u8, @truncate(rng >> 16)) ^ @as(u8, @truncate(rng));
    }
}

fn gen_iv() [16]u8 {
    var iv: [16]u8 = undefined;
    const t = @import("../arch/x86_64/isr.zig").get_ticks();
    fill_random(iv[0..], t);
    return iv;
}

fn process_net() void {
    var rx_pkt: [2048]u8 = undefined;
    const e1000_n = @import("../drivers/e1000.zig");
    if (e1000_n.receive_packet(rx_pkt[0..])) |len| {
        if (len == 0) return;
        const arp_n = @import("../net/arp.zig");
        arp_n.handle_packet(rx_pkt[0..len]);
        tcp.handle_packet(rx_pkt[0..len]);
        const udp_n = @import("../net/udp.zig");
        udp_n.handle_packet(rx_pkt[0..len]);
        const dhcp_n = @import("../net/dhcp.zig");
        dhcp_n.handle_packet(rx_pkt[0..len]);
    }
}

fn spin(n: u32) void {
    var i: u32 = 0;
    while (i < n) : (i += 1) {}
}
