package arithmetic

import chisel3._
import chisel3.util._
import nand._

// ═══════════════════════════════════════════════════════════════════
//  ARITHMETIC FROM NAND — Adders and ALU built entirely from
//  NAND-derived gates
//
//  Hierarchy: NAND2 → XOR/AND/OR → Half Adder → Full Adder →
//             Ripple Carry Adder → ALU slice
// ═══════════════════════════════════════════════════════════════════

// ─── HALF ADDER from NAND ────────────────────────────────────────
// sum = a ⊕ b
// cout = a · b

class HalfAdderFromNand extends Module {
  val io = IO(new Bundle {
    val a    = Input(Bool())
    val b    = Input(Bool())
    val sum  = Output(Bool())
    val cout = Output(Bool())
  })

  val xor = Module(new Xor2FromNand)
  xor.io.a := io.a
  xor.io.b := io.b
  io.sum := xor.io.y

  val and = Module(new And2FromNand)
  and.io.a := io.a
  and.io.b := io.b
  io.cout := and.io.y
}

// ─── FULL ADDER from NAND ────────────────────────────────────────
// sum = a ⊕ b ⊕ cin
// cout = (a·b) + (cin·(a⊕b))

class FullAdderFromNand extends Module {
  val io = IO(new Bundle {
    val a    = Input(Bool())
    val b    = Input(Bool())
    val cin  = Input(Bool())
    val sum  = Output(Bool())
    val cout = Output(Bool())
  })

  // First half adder: a, b
  val ha1 = Module(new HalfAdderFromNand)
  ha1.io.a := io.a
  ha1.io.b := io.b

  // Second half adder: (a⊕b), cin
  val ha2 = Module(new HalfAdderFromNand)
  ha2.io.a := ha1.io.sum
  ha2.io.b := io.cin

  io.sum := ha2.io.sum

  // cout = (a·b) + (cin·(a⊕b))
  val or = Module(new Or2FromNand)
  or.io.a := ha1.io.cout
  or.io.b := ha2.io.cout
  io.cout := or.io.y
}

// ─── RIPPLE CARRY ADDER from NAND ───────────────────────────────
// n-bit adder: chain of full adders, carry ripples LSB → MSB

class RippleCarryAdder(val n: Int) extends Module {
  val io = IO(new Bundle {
    val a    = Input(UInt(n.W))
    val b    = Input(UInt(n.W))
    val cin  = Input(Bool())
    val sum  = Output(UInt(n.W))
    val cout = Output(Bool())
  })

  val carries = Wire(Vec(n + 1, Bool()))
  carries(0) := io.cin

  val sums = Wire(Vec(n, Bool()))

  for (i <- 0 until n) {
    val fa = Module(new FullAdderFromNand)
    fa.io.a   := io.a(i)
    fa.io.b   := io.b(i)
    fa.io.cin := carries(i)
    sums(i)     := fa.io.sum
    carries(i+1) := fa.io.cout
  }

  io.sum  := Cat(sums.reverse)
  io.cout := carries(n)
}

// ─── ALU SLICE from NAND ────────────────────────────────────────
// 1-bit ALU slice with 4 operations selected by 2-bit opcode:
//   00 → AND
//   01 → OR
//   10 → XOR
//   11 → ADD (with carry in/out)
//
// All gates built from NAND2 primitive chain

class AluSliceFromNand extends Module {
  val io = IO(new Bundle {
    val a    = Input(Bool())
    val b    = Input(Bool())
    val cin  = Input(Bool())
    val op   = Input(UInt(2.W))
    val y    = Output(Bool())
    val cout = Output(Bool())
  })

  // AND path
  val andGate = Module(new And2FromNand)
  andGate.io.a := io.a
  andGate.io.b := io.b

  // OR path
  val orGate = Module(new Or2FromNand)
  orGate.io.a := io.a
  orGate.io.b := io.b

  // XOR path
  val xorGate = Module(new Xor2FromNand)
  xorGate.io.a := io.a
  xorGate.io.b := io.b

  // ADD path (full adder)
  val fa = Module(new FullAdderFromNand)
  fa.io.a   := io.a
  fa.io.b   := io.b
  fa.io.cin := io.cin

  // 4:1 MUX from two levels of 2:1 MUX
  // Level 1: mux0 selects AND/OR on op[0], mux1 selects XOR/ADD-sum on op[0]
  val mux0 = Module(new Mux2FromNand)
  mux0.io.a   := andGate.io.y   // op[0]=0 → AND
  mux0.io.b   := orGate.io.y    // op[0]=1 → OR
  mux0.io.sel := io.op(0)

  val mux1 = Module(new Mux2FromNand)
  mux1.io.a   := xorGate.io.y   // op[0]=0 → XOR
  mux1.io.b   := fa.io.sum      // op[0]=1 → ADD
  mux1.io.sel := io.op(0)

  // Level 2: select between level-1 results on op[1]
  val mux2 = Module(new Mux2FromNand)
  mux2.io.a   := mux0.io.y      // op[1]=0 → AND/OR
  mux2.io.b   := mux1.io.y      // op[1]=1 → XOR/ADD
  mux2.io.sel := io.op(1)

  io.y := mux2.io.y

  // Carry out: only meaningful for ADD (op=11), 0 otherwise
  // Mux carry: pass cout when op==3, else 0
  val is_add = Module(new And2FromNand)
  is_add.io.a := io.op(0)
  is_add.io.b := io.op(1)

  val carry_mux = Module(new Mux2FromNand)
  carry_mux.io.a   := false.B
  carry_mux.io.b   := fa.io.cout
  carry_mux.io.sel := is_add.io.y

  io.cout := carry_mux.io.y
}

// ─── n-BIT ALU from NAND ───────────────────────────────────────
// Ripple ALU: chain of AluSliceFromNand for ADD,
// parallel for AND/OR/XOR (carry only used for ADD)

class AluFromNand(val n: Int) extends Module {
  val io = IO(new Bundle {
    val a    = Input(UInt(n.W))
    val b    = Input(UInt(n.W))
    val cin  = Input(Bool())
    val op   = Input(UInt(2.W))
    val y    = Output(UInt(n.W))
    val cout = Output(Bool())
  })

  val carries = Wire(Vec(n + 1, Bool()))
  carries(0) := io.cin

  val results = Wire(Vec(n, Bool()))

  for (i <- 0 until n) {
    val slice = Module(new AluSliceFromNand)
    slice.io.a   := io.a(i)
    slice.io.b   := io.b(i)
    slice.io.cin := carries(i)
    slice.io.op  := io.op
    results(i)     := slice.io.y
    carries(i + 1) := slice.io.cout
  }

  io.y    := Cat(results.reverse)
  io.cout := carries(n)
}
