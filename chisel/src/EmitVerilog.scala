package nand

import chisel3._
import chisel3.stage.ChiselStage
import sequential._
import arithmetic._

// ═══════════════════════════════════════════════════════════════════
//  VERILOG EMISSION — Generates synthesizable Verilog from all
//  NAND-derived Chisel modules
//
//  Usage: sbt "runMain nand.EmitVerilog"
//  Output: phaser-ags-chisel.v in project root
// ═══════════════════════════════════════════════════════════════════

object EmitVerilog extends App {

  val modules: Seq[(String, () => chisel3.RawModule)] = Seq(
    // Primitives
    ("Nand2",       () => new Nand2),
    ("Nand3",       () => new Nand3),
    ("Nor2",        () => new Nor2),

    // Combinational from NAND
    ("InvFromNand",     () => new InvFromNand),
    ("And2FromNand",    () => new And2FromNand),
    ("Or2FromNand",     () => new Or2FromNand),
    ("Xor2FromNand",    () => new Xor2FromNand),
    ("Xnor2FromNand",   () => new Xnor2FromNand),
    ("Mux2FromNand",    () => new Mux2FromNand),

    // Sequential from NAND
    ("SrLatchFromNand",     () => new SrLatchFromNand),
    ("SrLatch",             () => new SrLatch),
    ("DLatchFromNand",      () => new DLatchFromNand),
    ("DFlipFlopFromNand",   () => new DFlipFlopFromNand),
    ("DFlipFlopResetFromNand", () => new DFlipFlopResetFromNand),
    ("RegisterFromNand8",   () => new RegisterFromNand(8)),

    // Arithmetic from NAND
    ("HalfAdderFromNand",   () => new HalfAdderFromNand),
    ("FullAdderFromNand",   () => new FullAdderFromNand),
    ("RippleCarryAdder8",   () => new RippleCarryAdder(8)),
    ("AluSliceFromNand",    () => new AluSliceFromNand),
    ("AluFromNand8",        () => new AluFromNand(8)),
  )

  for ((name, gen) <- modules) {
    println(s" Emitting Verilog: $name")
    (new ChiselStage).emitVerilog(
      gen(),
      Array("--target-dir", "verilog_out")
    )
  }

  println(s"\n Done. ${modules.size} modules → verilog_out/")
}
