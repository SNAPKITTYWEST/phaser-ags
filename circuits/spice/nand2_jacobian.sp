******************************************************************************
* SPICE DC ANALYSIS — JACOBIAN (CONDUCTANCE) MATRIX BLOCKS
* 
* In SPICE, the Newton-Raphson iteration for DC operating point solves:
*
*   J(x) · Δx = -F(x)
*
* where J(x) = ∂F/∂x is the Jacobian (conductance/stamp matrix).
* Each device contributes a "stamp" to the Jacobian.
*
* For the CMOS NAND gate, we show:
*   1. The full MNA (Modified Nodal Analysis) Jacobian structure
*   2. NMOS Jacobian stamps (BSIM3v3 linearized)
*   3. PMOS Jacobian stamps
*   4. The composite NAND2 Jacobian block
*   5. Iteration convergence sequence
******************************************************************************

******************************************************************************
* 1. MNA FORMULATION FOR NAND2
******************************************************************************
*
* Nodes:  0=GND, 1=VDD, 2=A, 3=B, 4=Y, 5=MID (NMOS series midpoint)
*
* Unknowns:  v4 (Y), v5 (MID)
*            i_vdd (VDD supply current — optional for power measurement)
*
* KCL at node 4 (Y):
*   i_MP1(v4,v2) + i_MP2(v4,v3) + i_MN3(v4,v2,v5) + C_load·dv4/dt = 0
*
* KCL at node 5 (MID):
*   i_MN4(v5,v3) - i_MN3(v4,v2,v5) + C_mid·dv5/dt = 0
*
* The Jacobian J = ∂F/∂[v4, v5] has the block structure:
*
*         ┌                              ┐
*         │  ∂i_Y/∂v4    ∂i_Y/∂v5      │
*   J  =  │                              │
*         │  ∂i_MID/∂v4  ∂i_MID/∂v5    │
*         └                              ┘
*
* where:
*   ∂i_Y/∂v4   = g_MP1 + g_MP2 + g_MN3_ds
*   ∂i_Y/∂v5   = -g_MN3_ds  (coupling through NMOS series)
*   ∂i_MID/∂v4 = g_MN3_ds   (reverse coupling)
*   ∂i_MID/∂v5 = -(g_MN3_ds + g_MN4_ds)
*
* g_xxx = drain-source conductance = ∂I_D/∂V_DS (linearized around operating point)

******************************************************************************
* 2. NMOS JACOBIAN STAMP (BSIM3v3 simplified)
******************************************************************************
*
* MOSFET small-signal model (linearized at operating point):
*
*   I_D = f(V_GS, V_DS, V_BS)
*
* The conductance terms (Jacobian entries) are:
*
*   g_m  = ∂I_D/∂V_GS      (transconductance)
*   g_ds = ∂I_D/∂V_DS      (output conductance)
*   g_mb = ∂I_D/∂V_BS      (body transconductance)
*
* MNA stamp for NMOS (drain=D, gate=G, source=S, body=B):
*
*           D        G        S        B
*     D  [ g_ds    g_m    -(g_ds+g_m) -g_mb ]
*     G  [  0       0        0         0     ]
*     S  [ -g_ds  -g_m   (g_ds+g_m)   g_mb  ]
*     B  [  0     -g_mb    g_mb        0     ]
*
* For NAND2 NMOS M3 (D=Y, G=A, S=MID, B=GND):
*   g_ds3, g_m3, g_mb3 are evaluated at V_GS3 = V_A - V_MID
*
* For NAND2 NMOS M4 (D=MID, G=B, S=GND, B=GND):
*   g_ds4, g_m4 evaluated at V_GS4 = V_B

******************************************************************************
* 3. PMOS JACOBIAN STAMP
******************************************************************************
*
* PMOS is the complement — current flows source→drain:
*
*   I_D = -f(V_SG, V_SD, V_SB)   (source-referenced)
*
*   g_m  = ∂|I_D|/∂V_SG
*   g_ds = ∂|I_D|/∂V_SD
*
* MNA stamp for PMOS (drain=D, gate=G, source=S, body=B):
*
*           D        G        S        B
*     D  [ g_ds    -g_m    -(g_ds-g_m) g_mb ]
*     S  [ -g_ds   g_m    (g_ds-g_m)  -g_mb ]
*     G  [  0       0        0         0     ]
*     B  [  0      -g_mb    g_mb       0     ]
*
* For NAND2 PMOS M1 (D=Y, G=A, S=VDD, B=VDD):
*   V_SG1 = VDD - V_A,  V_SD1 = VDD - V_Y

******************************************************************************
* 4. COMPOSITE NAND2 JACOBIAN (2×2 block for internal nodes Y, MID)
******************************************************************************

.SUBCKT NAND2_JAC A B Y VDD GND

* ---- PMOS M1: VDD→Y, gate=A ----
MP1 Y A VDD VDD pmos180 W=400n L=180n

* ---- PMOS M2: VDD→Y, gate=B ----
MP2 Y B VDD VDD pmos180 W=400n L=180n

* ---- NMOS M3: Y→MID, gate=A ----
MN3 Y   A MID  GND nmos180 W=400n L=180n

* ---- NMOS M4: MID→GND, gate=B ----
MN4 MID B GND  GND nmos180 W=400n L=180n

CMID MID GND 0.5f
CLOAD Y GND 10f

.ENDS NAND2_JAC

******************************************************************************
* 5. DC OPERATING POINT — Jacobian evaluation at each input combination
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

* Sweep inputs to evaluate Jacobian at all 4 corners
VA A 0 DC 0
VB B 0 DC 0

X1 A B Y VDD GND NAND2_JAC

* DC analysis: sweep A with B=0 and B=1.8
.DC VA 0 1.8 0.01

* Save operating point for Jacobian extraction
.SAVE @MP1[gm] @MP1[gds] @MP1[vgs] @MP1[vds]
.SAVE @MP2[gm] @MP2[gds] @MP2[vgs] @MP2[vds]
.SAVE @MN3[gm] @MN3[gds] @MN3[vgs] @MN3[vds]
.SAVE @MN4[gm] @MN4[gds] @MN4[vgs] @MN4[vds]
.SAVE V(Y) V(A) V(B)

.OPTIONS POST=2 OPFILE=1
.END
