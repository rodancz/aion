const LIMBS: usize = 32; // 2048 bits = 32 x 64-bit limbs

pub const BigInt = struct {
    limbs: [LIMBS]u64,

    pub fn zero() BigInt {
        return BigInt{ .limbs = [_]u64{0} ** LIMBS };
    }

    pub fn from_u64(v: u64) BigInt {
        var r = BigInt.zero();
        r.limbs[0] = v;
        return r;
    }

    pub fn from_bytes_be(bytes: []const u8) BigInt {
        var r = BigInt.zero();
        var bi: usize = 0;
        var i: usize = bytes.len;
        while (i > 0) {
            i -= 1;
            var limb_val: u64 = bytes[i];
            var shift: u6 = 0;
            while (i > 0 and shift < 56) {
                i -= 1;
                shift += 8;
                limb_val |= @as(u64, bytes[i]) << shift;
                if (shift == 56) break;
            }
            r.limbs[bi] = limb_val;
            bi += 1;
            if (bi >= LIMBS) break;
        }
        return r;
    }

    pub fn to_bytes_be(self: *const BigInt, out: []u8) void {
        var bi: usize = LIMBS;
        var oi: usize = 0;
        while (bi > 0) : (bi -= 1) {
            const limb = self.limbs[bi - 1];
            var shift: u6 = 56;
            while (shift >= 8) : (shift -= 8) {
                if (oi < out.len) {
                    out[oi] = @truncate(limb >> shift);
                    oi += 1;
                }
            }
            if (oi < out.len) {
                out[oi] = @truncate(limb);
                oi += 1;
            }
        }
        while (oi < out.len) : (oi += 1) out[oi] = 0;
    }

    pub fn byte_len(self: *const BigInt) usize {
        var bi: usize = LIMBS;
        while (bi > 0) : (bi -= 1) {
            if (self.limbs[bi - 1] != 0) {
                const l = self.limbs[bi - 1];
                var bits: u6 = 64;
                while (bits > 0) : (bits -= 8) {
                    if ((l >> (bits - 8)) & 0xFF != 0) return (bi - 1) * 8 + @as(usize, bits) / 8;
                }
                return bi * 8;
            }
        }
        return 1;
    }

    pub fn is_zero(self: *const BigInt) bool {
        for (self.limbs) |l| if (l != 0) return false;
        return true;
    }

    pub fn is_odd(self: *const BigInt) bool {
        return (self.limbs[0] & 1) != 0;
    }

    pub fn add(a: *const BigInt, b: *const BigInt) BigInt {
        var r = BigInt.zero();
        var carry: u64 = 0;
        var i: usize = 0;
        while (i < LIMBS) : (i += 1) {
            const sum = @as(u128, a.limbs[i]) + @as(u128, b.limbs[i]) + @as(u128, carry);
            r.limbs[i] = @truncate(sum);
            carry = @truncate(sum >> 64);
        }
        return r;
    }

    pub fn sub(a: *const BigInt, b: *const BigInt) BigInt {
        var r = BigInt.zero();
        var borrow: u64 = 0;
        var i: usize = 0;
        while (i < LIMBS) : (i += 1) {
            const av = @as(u128, a.limbs[i]);
            const bv = @as(u128, b.limbs[i]) + @as(u128, borrow);
            if (av >= bv) {
                r.limbs[i] = @truncate(av - bv);
                borrow = 0;
            } else {
                r.limbs[i] = @truncate(av +% (@as(u128, 1) << 64) -% bv);
                borrow = 1;
            }
        }
        return r;
    }

    pub fn mul(a: *const BigInt, b: *const BigInt) BigInt {
        var r = BigInt.zero();
        var i: usize = 0;
        while (i < LIMBS) : (i += 1) {
            if (a.limbs[i] == 0) continue;
            var carry: u64 = 0;
            var j: usize = 0;
            while (j < LIMBS - i) : (j += 1) {
                const prod = @as(u128, a.limbs[i]) * @as(u128, b.limbs[j]) + @as(u128, r.limbs[i + j]) + @as(u128, carry);
                r.limbs[i + j] = @truncate(prod);
                carry = @truncate(prod >> 64);
            }
        }
        return r;
    }

    pub fn shl(self: *const BigInt, bits: usize) BigInt {
        if (bits == 0) return self.*;
        const limb_shift = bits / 64;
        const bit_shift = @as(u6, @truncate(bits % 64));
        var r = BigInt.zero();
        var i: usize = LIMBS;
        while (i > limb_shift) : (i -= 1) {
            const src_i = i - 1 - limb_shift;
            if (bit_shift == 0) {
                r.limbs[i - 1] = self.limbs[src_i];
            } else {
                    r.limbs[i - 1] = self.limbs[src_i] << bit_shift;
                    if (src_i > 0 and bit_shift > 0) {
                        r.limbs[i - 1] |= self.limbs[src_i - 1] >> @as(u6, @truncate(64 - @as(u7, bit_shift)));
                    }
            }
        }
        return r;
    }

    pub fn cmp(a: *const BigInt, b: *const BigInt) i32 {
        var i: usize = LIMBS;
        while (i > 0) : (i -= 1) {
            if (a.limbs[i - 1] > b.limbs[i - 1]) return 1;
            if (a.limbs[i - 1] < b.limbs[i - 1]) return -1;
        }
        return 0;
    }

    /// a = a - b, return borrow
    fn sub_in_place(a: *BigInt, b: *const BigInt) u64 {
        var borrow: u64 = 0;
        var i: usize = 0;
        while (i < LIMBS) : (i += 1) {
            const av = @as(u128, a.limbs[i]);
            const bv = @as(u128, b.limbs[i]) + @as(u128, borrow);
            if (av >= bv) {
                a.limbs[i] = @truncate(av - bv);
                borrow = 0;
            } else {
                a.limbs[i] = @truncate(av +% (@as(u128, 1) << 64) -% bv);
                borrow = 1;
            }
        }
        return borrow;
    }

    /// r = a % m, assuming a is 2*LIMBS limbs
    pub fn mod_reduce(a_wide: []const u64, m: *const BigInt) BigInt {
        // Simple binary long division
        var r = BigInt.zero();
        var total_bits = (LIMBS * 2 - 1) * 64;
        while (total_bits > 0) : (total_bits -= 1) {
            const limb_idx = total_bits / 64;
            const bit: u6 = @truncate(total_bits % 64);
            const bit_val = (a_wide[limb_idx] >> bit) & 1;
            r = r.shl(1);
            r.limbs[0] |= bit_val;
            if (r.cmp(m) >= 0) {
                _ = r.sub_in_place(m);
            }
        }
        return r;
    }

    pub fn modpow(base: *const BigInt, exp: *const BigInt, mod: *const BigInt) BigInt {
        var result = BigInt.from_u64(1);
        var b = BigInt.zero();
        var i: usize = 0;
        while (i < LIMBS) : (i += 1) b.limbs[i] = base.limbs[i];

        // Reduce base modulo mod
        while (b.cmp(mod) >= 0) {
            _ = b.sub_in_place(mod);
        }

        var e_idx: usize = LIMBS;
        while (e_idx > 0) : (e_idx -= 1) {
            var bit: u7 = 64;
            while (bit > 0) : (bit -= 1) {
                // Square
                    const sq = result.mul(&result);
                var sq_wide: [LIMBS * 2]u64 = undefined;
                var sqi: usize = 0;
                while (sqi < LIMBS * 2) : (sqi += 1) sq_wide[sqi] = if (sqi < LIMBS) sq.limbs[sqi] else 0;
                // Actually need proper wide multiplication
                result = sq_mod(&sq_wide, mod);

                if ((exp.limbs[e_idx - 1] >> @as(u6, @truncate(bit - 1))) & 1 != 0) {
                    const prod = result.mul(&b);
                    var prod_wide: [LIMBS * 2]u64 = undefined;
                    var pi: usize = 0;
                    while (pi < LIMBS * 2) : (pi += 1) prod_wide[pi] = if (pi < LIMBS) prod.limbs[pi] else 0;
                    result = sq_mod(&prod_wide, mod);
                }
            }
        }
        return result;
    }
};

fn sq_mod(a: []const u64, mod: *const BigInt) BigInt {
    // Reduce 2*LIMBS-limb number modulo mod using long division
    var r = BigInt.zero();
    var total_bits = LIMBS * 2 * 64 - 1;
    while (total_bits > 0) : (total_bits -= 1) {
        const limb_idx = total_bits / 64;
        const bit: u6 = @truncate(total_bits % 64);
        r = r.shl(1);
        r.limbs[0] |= (a[limb_idx] >> bit) & 1;
        if (r.cmp(mod) >= 0) {
            _ = r.sub_in_place(mod);
        }
    }
    // Final bit
    r = r.shl(1);
    r.limbs[0] |= a[0] & 1;
    if (r.cmp(mod) >= 0) {
        _ = r.sub_in_place(mod);
    }
    return r;
}
