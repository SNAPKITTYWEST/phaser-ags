//! SPDX-License-Identifier: AGPL-3.0-or-later
//! Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
// ═══════════════════════════════════════════════════════════════════
//  PHASER AGS — Zig build configuration (Zig 0.13 / 0.14)
//
//  Target: RV32I + Zicsr + Zifencei, freestanding, ilp32 soft-float.
//    - RV32I        matches chisel/src/riscv/Rv32iCore.scala and the
//                   SV32 paging / 32-bit satp layout in memory.zig.
//    - Zicsr        csrr/csrw/csrs/csrc (start.S, driver.zig) — split
//                   out of the base ISA in LLVM; must be enabled.
//    - Zifencei     fence.i in start.S / driver.fenceI.
//    - no M         mul/div lower to compiler-rt (Zig links it in).
//  Override with e.g.  zig build -Dcpu=generic_rv32+m+zicsr+zifencei
// ═══════════════════════════════════════════════════════════════════

const std = @import("std");

pub fn build(b: *std.Build) void {
    const rv = std.Target.riscv;

    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .riscv32,
            .os_tag = .freestanding,
            .abi = .none,
            .cpu_model = .{ .explicit = &rv.cpu.generic_rv32 },
            .cpu_features_add = rv.featureSet(&.{ .zicsr, .zifencei }),
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
        // medany: PC-relative addressing; image sits at 0x20000000.
        // (`.kernel` is an x86-64 code model and is rejected for RISC-V.)
        .code_model = .medium,
    });

    // Paths are relative to zig/ (where build.zig lives), so the script
    // is kernel/kernel.ld — not kernel.ld.
    // Boot entry + trap vector live in assembly; nothing else pulls them in.
    kernel.addAssemblyFile(b.path("kernel/start.S"));
    kernel.setLinkerScript(b.path("kernel/kernel.ld"));

    b.installArtifact(kernel);

    // ── Raw binary for loading at 0x20000000 (JTAG / boot ROM) ──
    const bin = b.addObjCopy(kernel.getEmittedBin(), .{ .format = .bin });
    const install_bin = b.addInstallBinFile(bin.getOutput(), "phaser-ags-kernel.bin");
    b.getInstallStep().dependOn(&install_bin.step);

    // ── QEMU smoke run ──
    // NOTE: QEMU `virt` does NOT match this board: its RAM is at
    // 0x80000000 and its UART at 0x10000000, while this image links at
    // 0x20000000 and drives the OMAP3530 UART at 0x4806A000. Useful for
    // stepping with -s -S + gdb, not for console output.
    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-riscv32",
        "-machine", "virt",
        "-nographic",
        "-bios",    "none",
        "-kernel",
    });
    run_cmd.addArtifactArg(kernel);
    const run_step = b.step("run", "Run kernel in QEMU (riscv32 virt; see note in build.zig)");
    run_step.dependOn(&run_cmd.step);
}
