******************************************************************************
* NAND-BASED SR LATCH — Cross-coupled NAND2 gates
* Demonstrates: positive feedback, bistability, Jacobian eigenvalue analysis
*
*   ┌─────────────────┐
*   │  S ──┤NAND2├──┬── Q
*   │      └──────┘  │
*   │    ┌───────────┘
*   │    │  ┌──────┐
*   │    └──┤NAND2├── Qbar ── R
*   │       └──────┘
*   └─────────────────┘
*
* The cross-coupling creates a 2×2 Jacobian with interesting eigenvalues:
*   - In stable states: both eigenvalues < 0 (convergent)
*   - During metastability: one eigenvalue > 0 (positive feedback)
******************************************************************************

.INCLUDE nand2_cmos.sp

.SUBCKT SR_LATCH S R Q QBAR VDD GND
X1 S QBAR Q    VDD GND NAND2
X2 R Q    QBAR VDD GND NAND2
.ENDS SR_LATCH

******************************************************************************
* TESTBENCH
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

* SET pulse
VS S 0 PULSE(0 1.8 10n 100p 100p 5n 50n)
* RESET pulse
VR R 0 PULSE(0 1.8 30n 100p 100p 5n 50n)

X1 S R Q QBAR VDD GND SR_LATCH

.TRAN 1p 80n
.PRINT TRAN V(S) V(R) V(Q) V(QBAR)

* Measure propagation delay: SET → Q rises
.MEASURE TRAN t_set TRIG V(S) VAL=0.9 FALL=1 TARG V(Q) VAL=0.9 RISE=1

* Measure propagation delay: RESET → Q falls
.MEASURE TRAN t_reset TRIG V(R) VAL=0.9 FALL=1 TARG V(Q) VAL=0.9 FALL=1

******************************************************************************
* JACOBIAN EIGENVALUE ANALYSIS
*
* The SR latch cross-coupling creates a Jacobian where:
*   - Q and QBAR nodes are coupled through both NAND gates
*   - In stable state (Q=1, QBAR=0): Jacobian has 2 negative eigenvalues
*   - In metastable state (Q=QBAR≈0.9): one eigenvalue becomes positive
*     → positive feedback, system diverges from metastable point
*
* This is why SPICE can struggle with latches — the Jacobian
* near metastability is ill-conditioned (near-singular with
* one eigenvalue near zero).
******************************************************************************

.IC V(Q)=1.8 V(QBAR)=0
.OPTIONS POST=2 ITL1=500

.END
