package sequential

import chisel3._
import chisel3.util._
import nand._

// ═══════════════════════════════════════════════════════════════════
//  SEQUENTIAL LOGIC FROM NAND — Cross-coupled feedback structures
//
//  Matches sr_latch_jacobian.sp: cross-coupled NAND2 with
//  Jacobian eigenvalue analysis (bistability, metastability)
//
//  Hierarchy: NAND2 → SR Latch → D Latch → D Flip-Flop → Register
// ═══════════════════════════════════════════════════════════════════

// ─── SR LATCH from NAND ──────────────────────────────────────────
// Cross-coupled NAND2: S-active-low, R-active-low
//
//   ┌─────────────────┐
//   │  S'──┤NAND2├──┬── Q
//   │     └──────┘  │
//   │   ┌───────────┘
//   │   │  ┌──────┐
//   │   └──┤NAND2├── Qbar ── R'
//   │      └──────┘
//   └─────────────────┘
//
// Truth table (active-low inputs):
//   S'=1 R'=1 → hold   |  S'=0 R'=1 → Q=1 (SET)
//   S'=1 R'=0 → Q=0 (RESET) |  S'=0 R'=0 → invalid
//
// SPICE Jacobian: 2×2 with off-diagonal coupling from feedback;
// stable states have both eigenvalues < 0, metastable has one > 0.

class SrLatchFromNand extends Module {
  val io = IO(new Bundle {
    val s_n  = Input(Bool())   // Active-low set   (S' in SPICE)
    val r_n  = Input(Bool())   // Active-low reset  (R' in SPICE)
    val q    = Output(Bool())
    val qbar = Output(Bool())
  })

  // Gate 1: Q = NAND(S', Qbar)
  val g1 = Module(new Nand2)
  g1.io.a := io.s_n
  // g1.io.b driven by g2 output below (cross-coupling)

  // Gate 2: Qbar = NAND(R', Q)
  val g2 = Module(new Nand2)
  g2.io.a := io.r_n
  g2.io.b := g1.io.y

  // Cross-coupling: Q fed back to gate 2, Qbar fed back to gate 1
  g1.io.b := g2.io.y

  io.q    := g1.io.y
  io.qbar := g2.io.y
}

// ─── SR LATCH (active-high wrapper) ──────────────────────────────
// Common interface: S=1 sets, R=1 resets
// Internally inverts S and R for the NAND latch

class SrLatch extends Module {
  val io = IO(new Bundle {
    val s    = Input(Bool())   // Active-high set
    val r    = Input(Bool())   // Active-high reset
    val q    = Output(Bool())
    val qbar = Output(Bool())
  })

  val sn_inv = Module(new InvFromNand)   // S' = NOT(S)
  sn_inv.io.a := io.s

  val rn_inv = Module(new InvFromNand)   // R' = NOT(R)
  rn_inv.io.a := io.r

  val latch = Module(new SrLatchFromNand)
  latch.io.s_n := sn_inv.io.y
  latch.io.r_n := rn_inv.io.y

  io.q    := latch.io.q
  io.qbar := latch.io.qbar
}

// ─── D LATCH (transparent) from NAND ────────────────────────────
// When EN=1: Q follows D (transparent)
// When EN=0: Q holds last value
//
// Implementation: D → S, D' → R on internal SR latch
//   S = D·EN = AND(D, EN)
//   R = D'·EN = AND(NOT(D), EN)

class DLatchFromNand extends Module {
  val io = IO(new Bundle {
    val d  = Input(Bool())
    val en = Input(Bool())    // Enable (transparent when high)
    val q  = Output(Bool())
  })

  // S = D AND EN → NAND(D, EN) then invert
  val d_and_en = Module(new And2FromNand)
  d_and_en.io.a := io.d
  d_and_en.io.b := io.en

  // R = D' AND EN
  val d_inv = Module(new InvFromNand)
  d_inv.io.a := io.d

  val dn_and_en = Module(new And2FromNand)
  dn_and_en.io.a := d_inv.io.y
  dn_and_en.io.b := io.en

  val latch = Module(new SrLatch)
  latch.io.s := d_and_en.io.y
  latch.io.r := dn_and_en.io.y

  io.q := latch.io.q
}

// ─── D FLIP-FLOP (edge-triggered, master-slave) from NAND ──────
// Two D-latches in series, clock inverted on slave:
//   Master latch: transparent when CLK=1
//   Slave latch:  transparent when CLK=0
// → Data captured on falling CLK edge → Q updates on rising CLK
//
// For positive-edge triggering, invert clock to master:
//   Master: transparent when CLK=0
//   Slave:  transparent when CLK=1
// → Q updates on rising edge of CLK

class DFlipFlopFromNand extends Module {
  val io = IO(new Bundle {
    val d   = Input(Bool())
    val clk = Input(Bool())   // Rising-edge triggered
    val q   = Output(Bool())
  })

  // Invert clock for master: master transparent when CLK=0
  val clk_inv = Module(new InvFromNand)
  clk_inv.io.a := io.clk

  // Master latch: EN = NOT(CLK) → transparent when CLK=0
  val master = Module(new DLatchFromNand)
  master.io.d  := io.d
  master.io.en := clk_inv.io.y

  // Slave latch: EN = CLK → transparent when CLK=1
  val slave = Module(new DLatchFromNand)
  slave.io.d  := master.io.q
  slave.io.en := io.clk

  io.q := slave.io.q
}

// ─── D FLIP-FLOP with synchronous reset ─────────────────────────
// Reset takes effect on clock edge: D_eff = RESET ? 0 : D

class DFlipFlopResetFromNand extends Module {
  val io = IO(new Bundle {
    val d     = Input(Bool())
    val clk   = Input(Bool())
    val reset = Input(Bool())   // Synchronous reset (active-high)
    val q     = Output(Bool())
  })

  // D_eff = MUX(sel=reset, a=D, b=0)
  val mux = Module(new nand.Mux2FromNand)
  mux.io.a   := io.d
  mux.io.b   := false.B       // 0 when reset
  mux.io.sel := io.reset

  val ff = Module(new DFlipFlopFromNand)
  ff.io.d   := mux.io.y
  ff.io.clk := io.clk

  io.q := ff.io.q
}

// ─── n-BIT REGISTER from D flip-flops ───────────────────────────
// Parallel load, synchronous reset, edge-triggered

class RegisterFromNand(val n: Int) extends Module {
  val io = IO(new Bundle {
    val din   = Input(UInt(n.W))
    val clk   = Input(Bool())
    val reset = Input(Bool())
    val dout  = Output(UInt(n.W))
  })

  val bits = VecInit(Seq.fill(n)(Module(new DFlipFlopResetFromNand).io))

  for (i <- 0 until n) {
    bits(i).d     := io.din(i)
    bits(i).clk   := io.clk
    bits(i).reset := io.reset
  }

  io.dout := Cat(bits.map(_.q).reverse)
}
