export fn l2kernel_main() noreturn {
    var count: u64 = 0;
    while (true) {
        count += 1;

        if (count == 500) {
            const crash: *volatile u8 = @ptrFromInt(0xDEAD);
            crash.* = 0;
        }

        var i: u64 = 0;
        while (i < 1000000) : (i += 1) {}
    }
}
