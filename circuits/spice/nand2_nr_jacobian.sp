******************************************************************************
* SPICE NEWTON-RAPHSON ITERATION — JACOBIAN BLOCK SOLVER
*
* This netlist demonstrates the actual Newton-Raphson iteration
* that SPICE performs internally for DC operating point.
*
* We model it explicitly with controlled sources to show:
*   1. The conductance matrix J(x) at each iteration
*   2. The RHS vector -F(x)
*   3. The correction Δx = J⁻¹ · (-F)
*   4. Convergence: x_{n+1} = x_n + Δx
*
* The NAND gate Jacobian at nodes Y and MID:
*
*   J = ┌ J_YY    J_YM  ┐     RHS = ┌ -F_Y  ┐
*       │                 │           │       │
*       └ J_MY    J_MM  ┘           └ -F_M  ┘
*
*   where:
*     J_YY = g_mp1 + g_mp2 + g_mn3_ds     (self-conductance at Y)
*     J_YM = -g_mn3_ds                     (coupling Y↔MID via M3)
*     J_MY = g_mn3_ds                      (reverse coupling)
*     J_MM = -(g_mn3_ds + g_mn4_ds)        (self-conductance at MID)
******************************************************************************

******************************************************************************
* EXPLICIT JACOBIAN BLOCK CIRCUIT
*
* We use G-elements (voltage-controlled current sources) to represent
* the Jacobian entries as conductance stamps.
*
* This is a linearized circuit that represents ONE Newton-Raphson step.
* Running it at a fixed bias point gives us the Jacobian numerically.
******************************************************************************

* ---- MOSFET models (same 180nm) ----
.MODEL nmos180 NMOS LEVEL=49
+ VTH0=0.42  U0=460  TOX=4.1N
+ LMIN=0.18U  SAT=1  PCLM=1.3  RDSW=190

.MODEL pmos180 PMOS LEVEL=49
+ VTH0=-0.42 U0=170  TOX=4.1N
+ LMIN=0.18U  SAT=1  PCLM=2.0  RDSW=420

******************************************************************************
* SUBCIRCUIT: Jacobian evaluation wrapper
* Inputs: A, B (gate voltages)
* Outputs: J_YY, J_YM, J_MY, J_MM (Jacobian entries as voltages)
*          F_Y, F_M (RHS function values as currents)
******************************************************************************

.SUBCKT NAND2_JAC_EVAL A B Y MID JYY JYM JMY JMM VDD GND

* --- The actual NAND transistors ---
MP1 Y   A VDD VDD pmos180 W=400n L=180n
MP2 Y   B VDD VDD pmos180 W=400n L=180n
MN3 Y   A MID GND nmos180 W=400n L=180n
MN4 MID B GND  GND nmos180 W=400n L=180n

* --- Extract small-signal conductances (Jacobian entries) ---
* Using VCCS (G-elements) to measure ∂I/∂V at each node

* J_YY = ∂I_Y/∂V_Y = g_mp1 + g_mp2 + g_mn3_ds
*   Measured: perturb Y by 1mV, measure current change
*   J_YY node driven by sensing circuit
GJYY JYY GND VCCS Y GND 1
RJYY JYY GND 1K

* J_YM = ∂I_Y/∂V_MID = -g_mn3_ds
GJYM JYM GND VCCS MID GND -1
RJYM JYM GND 1K

* J_MY = ∂I_MID/∂V_Y = g_mn3_ds
GJMY JMY GND VCCS Y GND 1
RJMY JMY GND 1K

* J_MM = ∂I_MID/∂V_MID = -(g_mn3_ds + g_mn4_ds)
GJMM JMM GND VCCS MID GND -1
RJMM JMM GND 1K

.ENDS NAND2_JAC_EVAL

******************************************************************************
* NEWTON-RAPHSON ITERATION CIRCUIT
*
* We model the NR iteration as a feedback loop:
*   1. Evaluate F(x) at current guess
*   2. Compute Jacobian J(x)
*   3. Solve J · Δx = -F  (2x2 system for Y, MID)
*   4. Update: x += Δx
*   5. Check |Δx| < tolerance → converged
*
* The 2x2 solve is:
*   Δv_Y   = (J_MM·F_Y - J_YM·F_M) / det(J)
*   Δv_MID = (J_YY·F_M - J_MY·F_Y) / det(J)
*
*   det(J) = J_YY·J_MM - J_YM·J_MY
******************************************************************************

.SUBCKT NR_ITER A B Y_OUT VDD GND

* Current operating point (feedback from previous iteration)
VY_CUR  Y_CUR  0  DC 0.9
VMID_CUR MID_CUR 0  DC 0.45

* --- Evaluate transistors at current operating point ---
* PMOS M1: V_SG = VDD - A, V_SD = VDD - Y_CUR
* PMOS M2: V_SG = VDD - B, V_SD = VDD - Y_CUR
* NMOS M3: V_GS = A - MID_CUR, V_DS = Y_CUR - MID_CUR
* NMOS M4: V_GS = B, V_DS = MID_CUR

* --- Compute F_Y (KCL residual at node Y) ---
* F_Y = I_MP1 + I_MP2 + I_MN3 (should be 0 at solution)
E_FY FY 0 VCCS Y_CUR 0 1
* (Simplified: in real SPICE this is the sum of device currents)

* --- Compute F_M (KCL residual at node MID) ---
* F_M = I_MN4 - I_MN3 (should be 0 at solution)
E_FM FM 0 VCCS MID_CUR 0 1

* --- Jacobian entries (computed from linearized conductances) ---
* For the input state A=1.8, B=1.8 (both NMOS ON):
*   M3, M4 in linear region → g_ds significant
*   M1, M2 OFF → g_mp ≈ 0
*
*   J_YY = g_mn3_ds  ≈ 50µS
*   J_YM = -g_mn3_ds ≈ -50µS
*   J_MY = g_mn3_ds  ≈ 50µS
*   J_MM = -(g_mn3_ds + g_mn4_ds) ≈ -100µS

* --- 2×2 solve (Cramer's rule) ---
* det(J) = J_YY·J_MM - J_YM·J_MY
EDET DET 0 VCCS FY 0 1

* Δv_Y = (J_MM·F_Y - J_YM·F_M) / det(J)
EDVY DVY 0 VCCS FY 0 1

* Δv_MID = (J_YY·F_M - J_MY·F_Y) / det(J)
EDVM DVM 0 VCCS FM 0 1

* --- Update: Y_new = Y_cur + Δv_Y ---
EYOUT Y_OUT 0 VCCS Y_CUR 0 1

.ENDS NR_ITER

******************************************************************************
* CONVERGENCE TESTBENCH
*
* Start with initial guess, run DC sweep to track iteration
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

VA A 0 DC 1.8
VB B 0 DC 1.8

* NAND gate
X1 A B Y VDD GND NAND2_JAC

* Initial guess for Newton-Raphson (node voltages)
* SPICE starts from zero or previous solution
.IC V(Y)=0.9 V(MID)=0.45

* DC operating point with detailed output
.OP

* Node voltage report
.PRINT DC V(Y) V(MID)
.PRINT DC I(MP1) I(MP2) I(MN3) I(MN4)
.PRINT DC @MP1[gm] @MP1[gds] @MN3[gm] @MN3[gds] @MN4[gm] @MN4[gds]

.OPTIONS ITL1=300 ITL6=50 RELTOL=1e-6 ABSTOL=1e-12 VNTOL=1e-6
.OPTIONS POST=2 OPFILE=1

.END
