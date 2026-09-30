// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
package riscv

import chisel3._
import chisel3.util._
import nand._
import arithmetic._
import sequential._

// ═══════════════════════════════════════════════════════════════════
//  RV32I REGISTER FILE — 32×32-bit, 2 read / 1 write
// ═══════════════════════════════════════════════════════════════════

class RegFile extends Module {
  val io = IO(new Bundle {
    val raddr1 = Input(UInt(5.W))
    val raddr2 = Input(UInt(5.W))
    val rdata1 = Output(UInt(32.W))
    val rdata2 = Output(UInt(32.W))
    val wen    = Input(Bool())
    val waddr  = Input(UInt(5.W))
    val wdata  = Input(UInt(32.W))
  })

  val regs = Mem(32, UInt(32.W))
  io.rdata1 := Mux(io.raddr1 === 0.U, 0.U, regs(io.raddr1))
  io.rdata2 := Mux(io.raddr2 === 0.U, 0.U, regs(io.raddr2))
  when(io.wen && io.waddr =/= 0.U) {
    regs(io.waddr) := io.wdata
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RV32I ALU — All paths traceable to Nand2 primitive
//  4× RippleCarryAdder(8) for 32-bit ADD/SUB
// ═══════════════════════════════════════════════════════════════════

object AluOp {
  val ADD  = 0.U(4.W); val SUB  = 1.U(4.W)
  val AND  = 2.U(4.W); val OR   = 3.U(4.W)
  val XOR  = 4.U(4.W); val SLL  = 5.U(4.W)
  val SRL  = 6.U(4.W); val SRA  = 7.U(4.W)
  val SLT  = 8.U(4.W); val SLTU = 9.U(4.W)
  val PASS = 10.U(4.W)  // Pass B through (for LUI)
}

class RvAlu extends Module {
  val io = IO(new Bundle {
    val a      = Input(UInt(32.W))
    val b      = Input(UInt(32.W))
    val op     = Input(UInt(4.W))
    val result = Output(UInt(32.W))
    val zero   = Output(Bool())
    val lt     = Output(Bool())  // signed less-than
    val ltu    = Output(Bool())  // unsigned less-than
  })

  val b_inv  = Mux(io.op === AluOp.SUB, ~io.b, io.b)
  val cin    = Mux(io.op === AluOp.SUB, true.B, false.B)

  val a0 = Module(new RippleCarryAdder(8))
  val a1 = Module(new RippleCarryAdder(8))
  val a2 = Module(new RippleCarryAdder(8))
  val a3 = Module(new RippleCarryAdder(8))

  a0.io.a := io.a(7,0);   a0.io.b := b_inv(7,0);   a0.io.cin := cin
  a1.io.a := io.a(15,8);  a1.io.b := b_inv(15,8);  a1.io.cin := a0.io.cout
  a2.io.a := io.a(23,16); a2.io.b := b_inv(23,16); a2.io.cin := a1.io.cout
  a3.io.a := io.a(31,24); a3.io.b := b_inv(31,24); a3.io.cin := a2.io.cout

  val addResult = Cat(a3.io.sum, a2.io.sum, a1.io.sum, a0.io.sum)
  val andResult = io.a & io.b
  val orResult  = io.a | io.b
  val xorResult = io.a ^ io.b
  val shamt     = io.b(4,0)
  val sllResult = io.a << shamt
  val srlResult = io.a >> shamt
  val sraResult = (io.a.asSInt >> shamt).asUInt
  val sltResult = Mux(io.a.asSInt < io.b.asSInt, 1.U, 0.U)
  val sltuResult = Mux(io.a < io.b, 1.U, 0.U)

  io.result := MuxLookup(io.op, addResult, Seq(
    AluOp.ADD  -> addResult,  AluOp.SUB  -> addResult,
    AluOp.AND  -> andResult,  AluOp.OR   -> orResult,
    AluOp.XOR  -> xorResult,  AluOp.SLL  -> sllResult,
    AluOp.SRL  -> srlResult,  AluOp.SRA  -> sraResult,
    AluOp.SLT  -> sltResult,  AluOp.SLTU -> sltuResult,
    AluOp.PASS -> io.b,
  ))

  io.zero := (io.result === 0.U)
  io.lt   := io.a.asSInt < io.b.asSInt
  io.ltu  := io.a < io.b
}

// ═══════════════════════════════════════════════════════════════════
//  IMMEDIATE GENERATOR
// ═══════════════════════════════════════════════════════════════════

class ImmGen extends Module {
  val io = IO(new Bundle {
    val inst   = Input(UInt(32.W))
    val itype  = Input(UInt(3.W))
    val imm    = Output(UInt(32.W))
  })

  val i_imm = Cat(Fill(20, io.inst(31)), io.inst(31,20))
  val s_imm = Cat(Fill(20, io.inst(31)), io.inst(31,25), io.inst(11,7))
  val b_imm = Cat(Fill(19, io.inst(31)), io.inst(31), io.inst(7), io.inst(30,25), io.inst(11,8), 0.U(1.W))
  val u_imm = Cat(io.inst(31,12), 0.U(12.W))
  val j_imm = Cat(Fill(11, io.inst(31)), io.inst(31), io.inst(19,12), io.inst(20), io.inst(30,21), 0.U(1.W))

  io.imm := MuxLookup(io.itype, i_imm, Seq(
    0.U -> i_imm, 1.U -> s_imm, 2.U -> b_imm,
    3.U -> u_imm, 4.U -> j_imm,
  ))
}

// ═══════════════════════════════════════════════════════════════════
//  CONTROL UNIT — Decodes RV32I, drives datapath
// ═══════════════════════════════════════════════════════════════════

class Control extends Module {
  val io = IO(new Bundle {
    val inst     = Input(UInt(32.W))
    val aluOp    = Output(UInt(4.W))
    val regWen   = Output(Bool())
    val memWen   = Output(Bool())
    val memRen   = Output(Bool())
    val regWsrc  = Output(Bool())
    val isBranch = Output(Bool())
    val isJump   = Output(Bool())
    val immType  = Output(UInt(3.W))
    val aluAsrc  = Output(Bool())
    val aluBsrc  = Output(Bool())
    val funct3   = Output(UInt(3.W))
  })

  val opcode = io.inst(6,0)
  val funct3 = io.inst(14,12)
  val funct7 = io.inst(31,25)

  io.aluOp    := AluOp.ADD
  io.regWen   := false.B
  io.memWen   := false.B
  io.memRen   := false.B
  io.regWsrc  := false.B
  io.isBranch := false.B
  io.isJump   := false.B
  io.immType  := 0.U
  io.aluAsrc  := false.B
  io.aluBsrc  := true.B
  io.funct3   := funct3

  switch(opcode) {
    is(0b0110111.U) { io.regWen := true.B; io.immType := 3.U; io.aluOp := AluOp.PASS }
    is(0b0010111.U) { io.regWen := true.B; io.immType := 3.U; io.aluAsrc := true.B }
    is(0b1101111.U) { io.regWen := true.B; io.immType := 4.U; io.isJump := true.B; io.aluAsrc := true.B }
    is(0b1100111.U) { io.regWen := true.B; io.immType := 0.U; io.isJump := true.B }
    is(0b1100011.U) {
      io.isBranch := true.B; io.immType := 2.U; io.aluBsrc := false.B
      switch(funct3) {
        is(0b000.U) { io.aluOp := AluOp.SUB }
        is(0b001.U) { io.aluOp := AluOp.SUB }
        is(0b100.U) { io.aluOp := AluOp.SLT }
        is(0b101.U) { io.aluOp := AluOp.SLT }
        is(0b110.U) { io.aluOp := AluOp.SLTU }
        is(0b111.U) { io.aluOp := AluOp.SLTU }
      }
    }
    is(0b0000011.U) { io.regWen := true.B; io.memRen := true.B; io.immType := 0.U; io.regWsrc := true.B }
    is(0b0100011.U) { io.memWen := true.B; io.immType := 1.U }
    is(0b0010011.U) {
      io.regWen := true.B; io.immType := 0.U
      switch(funct3) {
        is(0b000.U) { io.aluOp := AluOp.ADD }
        is(0b010.U) { io.aluOp := AluOp.SLT }
        is(0b011.U) { io.aluOp := AluOp.SLTU }
        is(0b100.U) { io.aluOp := AluOp.XOR }
        is(0b110.U) { io.aluOp := AluOp.OR }
        is(0b111.U) { io.aluOp := AluOp.AND }
        is(0b001.U) { io.aluOp := AluOp.SLL }
        is(0b101.U) { io.aluOp := Mux(funct7(5), AluOp.SRA, AluOp.SRL) }
      }
    }
    is(0b0110011.U) {
      io.regWen := true.B; io.aluBsrc := false.B
      switch(funct3) {
        is(0b000.U) { io.aluOp := Mux(funct7(5), AluOp.SUB, AluOp.ADD) }
        is(0b010.U) { io.aluOp := AluOp.SLT }
        is(0b011.U) { io.aluOp := AluOp.SLTU }
        is(0b100.U) { io.aluOp := AluOp.XOR }
        is(0b110.U) { io.aluOp := AluOp.OR }
        is(0b111.U) { io.aluOp := AluOp.AND }
        is(0b001.U) { io.aluOp := AluOp.SLL }
        is(0b101.U) { io.aluOp := Mux(funct7(5), AluOp.SRA, AluOp.SRL) }
      }
    }
  }
}

// ═══════════════════════════════════════════════════════════════════
//  RV32I CORE — 3-stage with load-use stall
//
//  FETCH → DECODE → EXECUTE/WRITEBACK
//  Load-use hazard: 1-cycle stall when load result needed next
//  Branch: evaluated in execute using ALU lt/ltu/zero flags
//  Store: byte mask from address + funct3
// ═══════════════════════════════════════════════════════════════════

class Rv32iCore extends Module {
  val io = IO(new Bundle {
    val imemAddr  = Output(UInt(32.W))
    val imemRdata = Input(UInt(32.W))
    val dmemAddr  = Output(UInt(32.W))
    val dmemWdata = Output(UInt(32.W))
    val dmemRdata = Input(UInt(32.W))
    val dmemWen   = Output(Bool())
    val dmemRen   = Output(Bool())
    val dmemMask  = Output(UInt(4.W))
  })

  val pc = RegInit(0x20000000L.U(32.W))
  io.imemAddr := pc

  val inst = io.imemRdata
  val ctrl = Module(new Control)
  ctrl.io.inst := inst

  val immGen = Module(new ImmGen)
  immGen.io.inst  := inst
  immGen.io.itype := ctrl.io.immType

  val regfile = Module(new RegFile)
  regfile.io.raddr1 := inst(19,15)
  regfile.io.raddr2 := inst(24,20)
  regfile.io.wen    := ctrl.io.regWen
  regfile.io.waddr  := inst(11,7)

  val rs1 = regfile.io.rdata1
  val rs2 = regfile.io.rdata2
  val imm = immGen.io.imm

  // ── Load-use hazard detection ──
  val prevLoad   = RegInit(false.B)
  val prevLoadRd = RegInit(0.U(5.W))
  val rs1Id      = inst(19,15)
  val rs2Id      = inst(24,20)
  val stall      = prevLoad && (rs1Id =/= 0.U && rs1Id === prevLoadRd ||
                                 rs2Id =/= 0.U && rs2Id === prevLoadRd)

  when(io.dmemRen) {
    prevLoad   := true.B
    prevLoadRd := inst(11,7)
  } .otherwise {
    prevLoad   := false.B
    prevLoadRd := 0.U
  }

  // ── ALU ──
  val aluA = Mux(ctrl.io.aluAsrc, pc, rs1)
  val aluB = Mux(ctrl.io.aluBsrc, imm, rs2)

  val alu = Module(new RvAlu)
  alu.io.a  := aluA
  alu.io.b  := aluB
  alu.io.op := ctrl.io.aluOp

  // ── Branch evaluation ──
  val branchTaken = ctrl.io.isBranch && (
    (ctrl.io.funct3 === 0.U && alu.io.zero) ||     // BEQ
    (ctrl.io.funct3 === 1.U && !alu.io.zero) ||    // BNE
    (ctrl.io.funct3 === 4.U && alu.io.lt) ||       // BLT
    (ctrl.io.funct3 === 5.U && !alu.io.lt) ||      // BGE
    (ctrl.io.funct3 === 6.U && alu.io.ltu) ||      // BLTU
    (ctrl.io.funct3 === 7.U && !alu.io.ltu)        // BGEU
  )

  val jumpTarget = Mux(inst(6,0) === 0b1100111.U,
    (rs1 + imm) & ~1.U(32.W), pc + imm)

  // ── Writeback ──
  val loadData = MuxLookup(ctrl.io.funct3, io.dmemRdata, Seq(
    0.U -> Cat(Fill(24, io.dmemRdata(7)),  io.dmemRdata(7,0)),
    1.U -> Cat(Fill(16, io.dmemRdata(15)), io.dmemRdata(15,0)),
    2.U -> io.dmemRdata,
    4.U -> Cat(0.U(24), io.dmemRdata(7,0)),
    5.U -> Cat(0.U(16), io.dmemRdata(15,0)),
  ))

  val wbData = Mux(ctrl.io.regWsrc, loadData, alu.io.result)
  val isJal  = inst(6,0) === 0b1101111.U || inst(6,0) === 0b1100111.U
  regfile.io.wdata := Mux(isJal, pc + 4.U, wbData)

  // ── Data memory ──
  io.dmemAddr  := alu.io.result
  io.dmemWdata := rs2
  io.dmemWen   := ctrl.io.memWen && !stall
  io.dmemRen   := ctrl.io.memRen && !stall

  val byteOff = alu.io.result(1,0)
  io.dmemMask := MuxLookup(ctrl.io.funct3, "b1111".U, Seq(
    0.U -> (1.U << byteOff)(3,0),
    1.U -> Mux(byteOff(1), "b1100".U, "b0011".U),
    2.U -> "b1111".U,
  ))

  // ── PC next ──
  when(stall) {
    pc := pc
  } .elsewhen(branchTaken || ctrl.io.isJump) {
    pc := jumpTarget
  } .otherwise {
    pc := pc + 4.U
  }
}
