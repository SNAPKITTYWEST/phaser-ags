package nand

import chisel3._
import chisel3.util._

// ═══════════════════════════════════════════════════════════════════
// NAND2 — Primitive gate, maps 1:1 to the CMOS SPICE circuit
//
// SPICE: 2 PMOS parallel (pull-up) + 2 NMOS series (pull-down)
// Chisel: built-in operator, synthesizer maps to standard cell
// ═══════════════════════════════════════════════════════════════════

class Nand2 extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  io.y := ~(io.a & io.b)
}

// ═══════════════════════════════════════════════════════════════════
// NAND3 — 3 PMOS parallel + 3 NMOS series
// Matches nand3_jacobian.sp tridiagonal Jacobian
// ═══════════════════════════════════════════════════════════════════

class Nand3 extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val c = Input(Bool())
    val y = Output(Bool())
  })

  io.y := ~(io.a & io.b & io.c)
}

// ═══════════════════════════════════════════════════════════════════
// NOR2 — Complementary to NAND: 2 PMOS series + 2 NMOS parallel
// ═══════════════════════════════════════════════════════════════════

class Nor2 extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  io.y := ~(io.a | io.b)
}
