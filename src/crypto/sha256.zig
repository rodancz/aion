const K: [64]u32 = [_]u32{
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5,
    0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
    0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3,
    0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5,
    0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

pub const Sha256 = struct {
    state: [8]u32,
    buf: [64]u8,
    buf_len: usize,
    total_len: u64,

    pub fn init() Sha256 {
        return Sha256{
            .state = [_]u32{ 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 },
            .buf = [_]u8{0} ** 64,
            .buf_len = 0,
            .total_len = 0,
        };
    }

    pub fn update(self: *Sha256, data: []const u8) void {
        self.total_len += data.len;
        var di: usize = 0;
        while (di < data.len) {
            self.buf[self.buf_len] = data[di];
            self.buf_len += 1;
            di += 1;
            if (self.buf_len == 64) {
                compress(&self.state, self.buf[0..]);
                self.buf_len = 0;
            }
        }
    }

    pub fn finalize(self: *Sha256, out: []u8) void {
        // Padding
        self.buf[self.buf_len] = 0x80;
        self.buf_len += 1;

        if (self.buf_len > 56) {
            while (self.buf_len < 64) : (self.buf_len += 1) self.buf[self.buf_len] = 0;
            compress(&self.state, self.buf[0..]);
            self.buf_len = 0;
        }
        while (self.buf_len < 56) : (self.buf_len += 1) self.buf[self.buf_len] = 0;

        const bits = self.total_len * 8;
        self.buf[56] = @truncate(bits >> 56);
        self.buf[57] = @truncate(bits >> 48);
        self.buf[58] = @truncate(bits >> 40);
        self.buf[59] = @truncate(bits >> 32);
        self.buf[60] = @truncate(bits >> 24);
        self.buf[61] = @truncate(bits >> 16);
        self.buf[62] = @truncate(bits >> 8);
        self.buf[63] = @truncate(bits);

        compress(&self.state, self.buf[0..]);

        out[0] = @truncate(self.state[0] >> 24);
        out[1] = @truncate(self.state[0] >> 16);
        out[2] = @truncate(self.state[0] >> 8);
        out[3] = @truncate(self.state[0]);
        out[4] = @truncate(self.state[1] >> 24);
        out[5] = @truncate(self.state[1] >> 16);
        out[6] = @truncate(self.state[1] >> 8);
        out[7] = @truncate(self.state[1]);
        out[8] = @truncate(self.state[2] >> 24);
        out[9] = @truncate(self.state[2] >> 16);
        out[10] = @truncate(self.state[2] >> 8);
        out[11] = @truncate(self.state[2]);
        out[12] = @truncate(self.state[3] >> 24);
        out[13] = @truncate(self.state[3] >> 16);
        out[14] = @truncate(self.state[3] >> 8);
        out[15] = @truncate(self.state[3]);
        out[16] = @truncate(self.state[4] >> 24);
        out[17] = @truncate(self.state[4] >> 16);
        out[18] = @truncate(self.state[4] >> 8);
        out[19] = @truncate(self.state[4]);
        out[20] = @truncate(self.state[5] >> 24);
        out[21] = @truncate(self.state[5] >> 16);
        out[22] = @truncate(self.state[5] >> 8);
        out[23] = @truncate(self.state[5]);
        out[24] = @truncate(self.state[6] >> 24);
        out[25] = @truncate(self.state[6] >> 16);
        out[26] = @truncate(self.state[6] >> 8);
        out[27] = @truncate(self.state[6]);
        out[28] = @truncate(self.state[7] >> 24);
        out[29] = @truncate(self.state[7] >> 16);
        out[30] = @truncate(self.state[7] >> 8);
        out[31] = @truncate(self.state[7]);
    }

    pub fn hash(data: []const u8, out: []u8) void {
        var ctx = Sha256.init();
        ctx.update(data);
        ctx.finalize(out);
    }
};

fn compress(state: *[8]u32, block: []const u8) void {
    var w: [64]u32 = undefined;
    var i: usize = 0;
    while (i < 16) : (i += 1) {
        w[i] = (@as(u32, block[i * 4]) << 24) | (@as(u32, block[i * 4 + 1]) << 16) | (@as(u32, block[i * 4 + 2]) << 8) | block[i * 4 + 3];
    }
    i = 16;
    while (i < 64) : (i += 1) {
        const s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
        const s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
        w[i] = w[i - 16] +% s0 +% w[i - 7] +% s1;
    }

    var a = state[0];
    var b = state[1];
    var c = state[2];
    var d = state[3];
    var e = state[4];
    var f = state[5];
    var g = state[6];
    var h = state[7];

    i = 0;
    while (i < 64) : (i += 1) {
        const s1_e = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        const ch = (e & f) ^ (~e & g);
        const temp1 = h +% s1_e +% ch +% K[i] +% w[i];
        const s0_a = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        const maj = (a & b) ^ (a & c) ^ (b & c);
        const temp2 = s0_a +% maj;

        h = g;
        g = f;
        f = e;
        e = d +% temp1;
        d = c;
        c = b;
        b = a;
        a = temp1 +% temp2;
    }

    state[0] +%= a;
    state[1] +%= b;
    state[2] +%= c;
    state[3] +%= d;
    state[4] +%= e;
    state[5] +%= f;
    state[6] +%= g;
    state[7] +%= h;
}

inline fn rotr(x: u32, n: u32) u32 {
    return (x >> @truncate(n)) | (x << @truncate(32 - n));
}

pub fn hmac_sha256(key: []const u8, message: []const u8, out: []u8) void {
    var key_block: [64]u8 = [_]u8{0} ** 64;
    if (key.len > 64) {
        Sha256.hash(key, key_block[0..32]);
    } else {
        var i: usize = 0;
        while (i < key.len) : (i += 1) key_block[i] = key[i];
    }

    var ipad: [64]u8 = undefined;
    var opad: [64]u8 = undefined;
    var i: usize = 0;
    while (i < 64) : (i += 1) {
        ipad[i] = key_block[i] ^ 0x36;
        opad[i] = key_block[i] ^ 0x5c;
    }

    var inner_hash: [32]u8 = undefined;
    var inner_ctx = Sha256.init();
    inner_ctx.update(ipad[0..]);
    inner_ctx.update(message);
    inner_ctx.finalize(inner_hash[0..]);

    var outer_ctx = Sha256.init();
    outer_ctx.update(opad[0..]);
    outer_ctx.update(inner_hash[0..]);
    outer_ctx.finalize(out);
}

pub fn tls_prf_sha256(secret: []const u8, label: []const u8, seed: []const u8, out: []u8) void {
    var a: [32]u8 = undefined;
    var input: [256]u8 = undefined;
    var in_len: usize = 0;
    var i: usize = 0;
    while (i < label.len) : (i += 1) { input[in_len] = label[i]; in_len += 1; }
    i = 0;
    while (i < seed.len) : (i += 1) { input[in_len] = seed[i]; in_len += 1; }

    var oi: usize = 0;
    while (oi < out.len) {
        // A(0) = seed on first iteration, A(i) = HMAC(secret, A(i-1)) on subsequent
        if (oi == 0) {
            hmac_sha256(secret, input[0..in_len], a[0..]);
        } else {
            hmac_sha256(secret, a[0..], a[0..]);
        }

        var hash_input: [288]u8 = undefined;
        var hi: usize = 0;
        var j: usize = 0;
        while (j < 32) : (j += 1) { hash_input[hi] = a[j]; hi += 1; }
        j = 0;
        while (j < in_len) : (j += 1) { hash_input[hi] = input[j]; hi += 1; }

        var chunk: [32]u8 = undefined;
        hmac_sha256(secret, hash_input[0..hi], chunk[0..]);

        j = 0;
        while (j < 32 and oi < out.len) : (j += 1) {
            out[oi] = chunk[j];
            oi += 1;
        }
    }
}
