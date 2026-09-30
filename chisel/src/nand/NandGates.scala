package nand

import chisel3._
import chisel3.util._

// ═══════════════════════════════════════════════════════════════════
//  BOOLEAN ALGEBRA FROM NAND — Chisel equivalents
//
//  Matches nand_derived_gates.sp: NOT, AND, OR, XOR all from NAND2
//  Each uses ONLY the Nand2 primitive (no built-in operators)
// ═══════════════════════════════════════════════════════════════════

// ─── NOT from NAND:  ¬a = NAND(a, a) ───────────────────────────────
// Proof: (a·a)' = a'  [Idempotent law]

class InvFromNand extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val y = Output(Bool())
  })

  val nand = Module(new Nand2)
  nand.io.a := io.a
  nand.io.b := io.a
  io.y := nand.io.y
}

// ─── AND from NAND:  a∧b = NAND(NAND(a,b), NAND(a,b)) ─────────────
// Proof: (a·b)'' = a·b  [Double complement]

class And2FromNand extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  val n1 = Module(new Nand2)
  n1.io.a := io.a
  n1.io.b := io.b

  val inv = Module(new InvFromNand)
  inv.io.a := n1.io.y
  io.y := inv.io.y
}

// ─── OR from NAND:  a∨b = NAND(NAND(a,a), NAND(b,b)) ──────────────
// Proof: (a'·b')' = a''+b'' = a+b  [De Morgan's law]

class Or2FromNand extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  val na = Module(new Nand2)   // NAND(a,a) = a'
  na.io.a := io.a
  na.io.b := io.a

  val nb = Module(new Nand2)   // NAND(b,b) = b'
  nb.io.a := io.b
  nb.io.b := io.b

  val or = Module(new Nand2)   // NAND(a', b') = (a'·b')' = a+b
  or.io.a := na.io.y
  or.io.b := nb.io.y
  io.y := or.io.y
}

// ─── XOR from NAND:  a⊕b = NAND(NAND(a,NAND(a,b)), NAND(b,NAND(a,b)))
// Proof:
//   n  = (a·b)'
//   an = (a·n)'  = (a·(a·b)')'
//   bn = (b·n)'  = (b·(a·b)')'
//   y  = (an·bn)' = XOR

class Xor2FromNand extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  val n  = Module(new Nand2)   // n = NAND(a, b)
  n.io.a := io.a
  n.io.b := io.b

  val an = Module(new Nand2)   // an = NAND(a, n)
  an.io.a := io.a
  an.io.b := n.io.y

  val bn = Module(new Nand2)   // bn = NAND(b, n)
  bn.io.a := io.b
  bn.io.b := n.io.y

  val xor = Module(new Nand2)  // y = NAND(an, bn) = XOR
  xor.io.a := an.io.y
  xor.io.b := bn.io.y
  io.y := xor.io.y
}

// ─── XNOR from NAND:  a⊙b = NOT(XOR) ──────────────────────────────

class Xnor2FromNand extends Module {
  val io = IO(new Bundle {
    val a = Input(Bool())
    val b = Input(Bool())
    val y = Output(Bool())
  })

  val xor = Module(new Xor2FromNand)
  xor.io.a := io.a
  xor.io.b := io.b

  val inv = Module(new InvFromNand)
  inv.io.a := xor.io.y
  io.y := inv.io.y
}

// ═══════════════════════════════════════════════════════════════════
//  MUX2 from NAND — 2:1 multiplexer
//  y = NAND(NAND(s,a'), NAND(s',b))   ... or simpler:
//  y = (s·a')' when s=0: NAND(s,a')=NAND(0,1)=1, NAND(s',b)=NAND(1,b)=b'
//  Simplified: y = NAND(NAND(s, a), NAND(s', b))  [active-low select]
// ═══════════════════════════════════════════════════════════════════

class Mux2FromNand extends Module {
  val io = IO(new Bundle {
    val a   = Input(Bool())   // Selected when s=0
    val b   = Input(Bool())   // Selected when s=1
    val sel = Input(Bool())
    val y   = Output(Bool())
  })

  val ns  = Module(new InvFromNand)   // sel'
  ns.io.a := io.sel

  val na  = Module(new Nand2)         // NAND(sel', a)
  na.io.a := ns.io.y
  na.io.b := io.a

  val nb  = Module(new Nand2)         // NAND(sel, b)
  nb.io.a := io.sel
  nb.io.b := io.b

  val out = Module(new Nand2)         // NAND(na, nb) = MUX
  out.io.a := na.io.y
  out.io.b := nb.io.y
  io.y := out.io.y
}
