//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty � https://github.com/SNAPKITTYWEST/phaser-ags
// ═══════════════════════════════════════════════════════════════════
//  PHASER AGS — Zig build configuration
//  Target: RISC-V 64-bit, freestanding (no OS)
// ═══════════════════════════════════════════════════════════════════

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv64,
            .os_tag = .freestanding,
            .abi = .none,
        },
    });

    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    const kernel = b.addExecutable(.{
        .name = "phaser-ags-kernel",
        .root_source_file = b.path("kernel/main.zig"),
        .target = target,
        .optimize = optimize,
        .linker_script = b.path("kernel.ld"),
    });

    kernel.setLinkerScriptPath(b.path("kernel.ld"));
    kernel.code_model = .kernel;

    b.installArtifact(kernel);

    // QEMU run target
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv64",
        "-machine", "virt",
        "-nographic",
        "-bios", "none",
        "-kernel", b.getInstallPath(.bin, "phaser-ags-kernel"),
    });
    const run_step = b.step("run", "Run kernel in QEMU");
    run_step.dependOn(&run_cmd.step);
}
