// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright 2025 Ahmad Ali Parr / SnapKitty — https://github.com/SNAPKITTYWEST/phaser-ags
package nand

import chisel3._
import chiseltest._
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatest.matchers.should.Matchers

// ═══════════════════════════════════════════════════════════════════
//  TEST HARNESSES — ChiselTest verification for all NAND-derived
//  modules. Truth tables match SPICE circuit simulation results.
// ═══════════════════════════════════════════════════════════════════

class Nand2Test extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Nand2"

  it should "match NAND truth table" in {
    test(new Nand2) { dut =>
      for (a <- Seq(false, true); b <- Seq(false, true)) {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.y.expect(!(a && b).B)
      }
    }
  }
}

class Nand3Test extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Nand3"

  it should "match 3-input NAND truth table" in {
    test(new Nand3) { dut =>
      for {
        a <- Seq(false, true)
        b <- Seq(false, true)
        c <- Seq(false, true)
      } {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.io.c.poke(c.B)
        dut.clock.step(1)
        dut.io.y.expect(!(a && b && c).B)
      }
    }
  }
}

class InvFromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "InvFromNand"

  it should "invert" in {
    test(new InvFromNand) { dut =>
      dut.io.a.poke(false.B); dut.clock.step(1); dut.io.y.expect(true.B)
      dut.io.a.poke(true.B);  dut.clock.step(1); dut.io.y.expect(false.B)
    }
  }
}

class And2FromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "And2FromNand"

  it should "match AND truth table" in {
    test(new And2FromNand) { dut =>
      for (a <- Seq(false, true); b <- Seq(false, true)) {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.y.expect((a && b).B)
      }
    }
  }
}

class Or2FromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Or2FromNand"

  it should "match OR truth table" in {
    test(new Or2FromNand) { dut =>
      for (a <- Seq(false, true); b <- Seq(false, true)) {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.y.expect((a || b).B)
      }
    }
  }
}

class Xor2FromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Xor2FromNand"

  it should "match XOR truth table" in {
    test(new Xor2FromNand) { dut =>
      for (a <- Seq(false, true); b <- Seq(false, true)) {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.y.expect((a ^ b).B)
      }
    }
  }
}

class Xnor2FromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Xnor2FromNand"

  it should "match XNOR truth table" in {
    test(new Xnor2FromNand) { dut =>
      for (a <- Seq(false, true); b <- Seq(false, true)) {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.y.expect(!(a ^ b).B)
      }
    }
  }
}

class Mux2FromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "Mux2FromNand"

  it should "select a when sel=0, b when sel=1" in {
    test(new Mux2FromNand) { dut =>
      for (sel <- Seq(false, true)) {
        for (a <- Seq(false, true); b <- Seq(false, true)) {
          dut.io.a.poke(a.B)
          dut.io.b.poke(b.B)
          dut.io.sel.poke(sel.B)
          dut.clock.step(1)
          dut.io.y.expect((if (sel) b else a).B)
        }
      }
    }
  }
}

// ─── Sequential tests ─────────────────────────────────────────────

class SrLatchFromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "SrLatchFromNand"

  it should "SET, HOLD, RESET correctly" in {
    test(new SrLatchFromNand) { dut =>
      // Initial: hold (both inactive-high)
      dut.io.s_n.poke(true.B)
      dut.io.r_n.poke(true.B)
      dut.clock.step(1)

      // SET: S'=0
      dut.io.s_n.poke(false.B)
      dut.clock.step(2)
      dut.io.q.expect(true.B)
      dut.io.qbar.expect(false.B)

      // HOLD
      dut.io.s_n.poke(true.B)
      dut.io.r_n.poke(true.B)
      dut.clock.step(2)
      dut.io.q.expect(true.B)

      // RESET: R'=0
      dut.io.r_n.poke(false.B)
      dut.clock.step(2)
      dut.io.q.expect(false.B)
      dut.io.qbar.expect(true.B)

      // HOLD after reset
      dut.io.r_n.poke(true.B)
      dut.clock.step(2)
      dut.io.q.expect(false.B)
    }
  }
}

class DFlipFlopFromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "DFlipFlopFromNand"

  it should "capture D on rising clock edge" in {
    test(new DFlipFlopFromNand) { dut =>
      // Set D=1, clock low → nothing captured
      dut.io.d.poke(true.B)
      dut.io.clk.poke(false.B)
      dut.clock.step(2)

      // Rising edge → capture D=1
      dut.io.clk.poke(true.B)
      dut.clock.step(2)
      dut.io.q.expect(true.B)

      // Change D while clock high → Q holds
      dut.io.d.poke(false.B)
      dut.clock.step(2)
      dut.io.q.expect(true.B)

      // Falling edge → Q still holds
      dut.io.clk.poke(false.B)
      dut.clock.step(2)
      dut.io.q.expect(true.B)

      // Next rising edge with D=0 → capture 0
      dut.io.clk.poke(true.B)
      dut.clock.step(2)
      dut.io.q.expect(false.B)
    }
  }
}

// ─── Arithmetic tests ─────────────────────────────────────────────

class HalfAdderFromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "HalfAdderFromNand"

  it should "match half-adder truth table" in {
    test(new HalfAdderFromNand) { dut =>
      Map(
        (false, false) -> (false, false),
        (false, true)  -> (true,  false),
        (true,  false) -> (true,  false),
        (true,  true)  -> (false, true),
      ).foreach { case ((a, b), (sum, cout)) =>
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.clock.step(1)
        dut.io.sum.expect(sum.B)
        dut.io.cout.expect(cout.B)
      }
    }
  }
}

class FullAdderFromNandTest extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "FullAdderFromNand"

  it should "match full-adder truth table" in {
    test(new FullAdderFromNand) { dut =>
      for {
        a    <- Seq(false, true)
        b    <- Seq(false, true)
        cin  <- Seq(false, true)
      } {
        dut.io.a.poke(a.B)
        dut.io.b.poke(b.B)
        dut.io.cin.poke(cin.B)
        dut.clock.step(1)
        val total = (if (a) 1 else 0) + (if (b) 1 else 0) + (if (cin) 1 else 0)
        dut.io.sum.expect((total % 2 == 1).B)
        dut.io.cout.expect((total >= 2).B)
      }
    }
  }
}

class RippleCarryAdder8Test extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "RippleCarryAdder8"

  it should "add correctly for various operand pairs" in {
    test(new RippleCarryAdder(8)) { dut =>
      val testCases = Seq(
        (0, 0, 0),
        (1, 1, 0),
        (42, 73, 0),
        (127, 128 % 256, 0),
        (200, 55, 0),
        (255, 1, 0),
        (255, 255, 0),
        (255, 255, 1),
      )

      for ((a, b, cin) <- testCases) {
        dut.io.a.poke(a.U)
        dut.io.b.poke(b.U)
        dut.io.cin.poke((cin == 1).B)
        dut.clock.step(1)
        val expected = (a + b + cin) % 256
        val carryOut = (a + b + cin) >= 256
        dut.io.sum.expect(expected.U)
        dut.io.cout.expect(carryOut.B)
      }
    }
  }
}

class AluFromNand8Test extends AnyFlatSpec with ChiselScalatestTester with Matchers {
  behavior of "AluFromNand8"

  it should "perform AND, OR, XOR, ADD correctly" in {
    test(new AluFromNand(8)) { dut =>
      // AND: op=00
      dut.io.op.poke(0.U)
      dut.io.a.poke(0xFF.U); dut.io.b.poke(0x55.U)
      dut.clock.step(1)
      dut.io.y.expect(0x55.U)

      // OR: op=01
      dut.io.op.poke(1.U)
      dut.io.a.poke(0x0F.U); dut.io.b.poke(0xF0.U)
      dut.clock.step(1)
      dut.io.y.expect(0xFF.U)

      // XOR: op=10
      dut.io.op.poke(2.U)
      dut.io.a.poke(0xFF.U); dut.io.b.poke(0x55.U)
      dut.clock.step(1)
      dut.io.y.expect(0xAA.U)

      // ADD: op=11
      dut.io.op.poke(3.U)
      dut.io.cin.poke(false.B)
      dut.io.a.poke(42.U); dut.io.b.poke(73.U)
      dut.clock.step(1)
      dut.io.y.expect(115.U)
    }
  }
}
