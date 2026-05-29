const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86_64,
        .os_tag = .freestanding,
        .abi = .none,
    });
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const nasm_run = b.addSystemCommand(&.{
        "nasm",
        "-f", "elf64",
        "-o",
    });
    const boot_obj = nasm_run.addOutputFileArg("boot.o");
    nasm_run.addFileArg(b.path("src/boot.asm"));

    const exe = b.addExecutable(.{
        .name = "cpumain",
        .root_module = mod,
    });

    exe.setLinkerScript(b.path("src/link.ld"));
    exe.step.dependOn(&nasm_run.step);
    exe.addObjectFile(boot_obj);

    b.installArtifact(exe);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-x86_64",
        "-kernel",
    });
    run_cmd.addFileArg(exe.getEmittedBin());
    run_cmd.addArgs(&.{
        "-m", "256M",
        "-serial", "stdio",
        "-display", "none",
        "-no-reboot",
        "-no-shutdown",
    });

    const run_step = b.step("run", "Run in QEMU");
    run_step.dependOn(&run_cmd.step);
}
