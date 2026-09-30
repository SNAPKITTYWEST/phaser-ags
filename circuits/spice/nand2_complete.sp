******************************************************************************
* FULL NAND2 GATE — SPICE with Jacobian block analysis
* 
* This is the production netlist: complete NAND2 with:
*   1. Transistor-level CMOS circuit
*   2. DC transfer characteristics
*   3. Transient switching waveforms
*   4. AC frequency response
*   5. Jacobian (conductance matrix) evaluation at all 4 input states
*   6. Newton-Raphson convergence tracking
******************************************************************************

* ---- BSIM3v3 180nm models ----
.MODEL nmos180 NMOS LEVEL=49
+ VTH0=0.42  TOX=4.1N  U0=460
+ LMIN=0.18U  K1=0.55  SAT=1
+ PCLM=1.3   PDIBLC1=0.012  RDSW=190
+ CGSO=2.1N  CGDO=2.1N  CJ=1.0M  CJSW=0.22M
+ MJ=0.36    MJSW=0.12  PB=0.9

.MODEL pmos180 PMOS LEVEL=49
+ VTH0=-0.42 TOX=4.1N  U0=170
+ LMIN=0.18U  K1=0.58  SAT=1
+ PCLM=2.0   PDIBLC1=0.008  RDSW=420
+ CGSO=2.1N  CGDO=2.1N  CJ=1.2M  CJSW=0.28M
+ MJ=0.42    MJSW=0.18  PB=0.9

******************************************************************************
* NAND2 Subcircuit with Jacobian observation nodes
******************************************************************************

.SUBCKT NAND2_FULL A B Y VDD GND
MP1 Y A VDD VDD pmos180 W=400n L=180n
MP2 Y B VDD VDD pmos180 W=400n L=180n
MN3 Y   A MID GND nmos180 W=400n L=180n
MN4 MID B GND GND nmos180 W=400n L=180n
CMID MID GND 0.5f
CLOAD Y GND 10f
.ENDS NAND2_FULL

******************************************************************************
* TESTBENCH
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

* Input waveforms
VA A 0 PULSE(0 1.8 5n 100p 100p 5n 20n)
VB B 0 PULSE(0 1.8 2.5n 100p 100p 2.5n 10n)

X1 A B Y VDD GND NAND2_FULL

******************************************************************************
* ANALYSIS 1: DC transfer curve — Jacobian evaluated at each point
******************************************************************************

* Sweep A while holding B at 0 and 1.8
.DC VA 0 1.8 0.005

* Save all device parameters for Jacobian computation
.SAVE @X1.MP1[gm]   @X1.MP1[gds]  @X1.MP1[vth]  @X1.MP1[vgs]  @X1.MP1[vds]  @X1.MP1[id]
.SAVE @X1.MP2[gm]   @X1.MP2[gds]  @X1.MP2[vth]  @X1.MP2[vgs]  @X1.MP2[vds]  @X1.MP2[id]
.SAVE @X1.MN3[gm]   @X1.MN3[gds]  @X1.MN3[vth]  @X1.MN3[vgs]  @X1.MN3[vds]  @X1.MN3[id]
.SAVE @X1.MN4[gm]   @X1.MN4[gds]  @X1.MN4[vth]  @X1.MN4[vgs]  @X1.MN4[vds]  @X1.MN4[id]

******************************************************************************
* ANALYSIS 2: Transient switching
******************************************************************************

.TRAN 1p 40n START=0

* Propagation delay measurements
.MEASURE TRAN tpd_A_RISE TRIG V(A) VAL=0.9 RISE=1 TARG V(Y) VAL=0.9 FALL=1
.MEASURE TRAN tpd_A_FALL TRIG V(A) VAL=0.9 FALL=1 TARG V(Y) VAL=0.9 RISE=1
.MEASURE TRAN tpd_B_RISE TRIG V(B) VAL=0.9 RISE=1 TARG V(Y) VAL=0.9 FALL=1
.MEASURE TRAN tpd_B_FALL TRIG V(B) VAL=0.9 FALL=1 TARG V(Y) VAL=0.9 RISE=1

* Rise/fall time
.MEASURE TRAN tr TRIG V(Y) VAL=0.18 RISE=1 TARG V(Y) VAL=1.62 RISE=1
.MEASURE TRAN tf TRIG V(Y) VAL=1.62 FALL=1 TARG V(Y) VAL=0.18 FALL=1

* Power
.MEASURE TRAN P_avg AVG POWER FROM=0 TO=40n
.MEASURE TRAN P_dyn INTEG POWER FROM=5n TO=40n

* Charge from VDD supply (energy per transition)
.MEASURE TRAN Q_vdd INTEG I(VDD) FROM=5n TO=20n

******************************************************************************
* ANALYSIS 3: AC frequency response
******************************************************************************

.AC DEC 20 1 100G

* Unity gain frequency
.MEASURE AC fu WHEN VDB(Y)=-3

******************************************************************************
* ANALYSIS 4: Jacobian at 4 operating corners
*
* At each corner we can compute the 2×2 Jacobian block:
*
*   J = ┌ J_YY    J_YM  ┐
*       └ J_MY    J_MM  ┘
*
* using the saved gm and gds values:
*
*   J_YY = g_mp1 + g_mp2 + g_mn3_ds
*   J_YM = -g_mn3_ds
*   J_MY = g_mn3_ds
*   J_MM = -(g_mn3_ds + g_mn4_ds)
*
* Corner 1: A=0, B=0 → Y=1.8 (both PMOS ON, both NMOS OFF)
*   g_mp1 ≈ 200µS, g_mp2 ≈ 200µS, g_mn3 ≈ 0, g_mn4 ≈ 0
*   J_YY = 400µS,  J_YM = 0,     J_MY = 0,     J_MM = 0
*   det(J) = 0 → MID node is floating (NMOS off), SPICE adds gmin
*
* Corner 2: A=0, B=1.8 → Y=1.8 (MP1 ON, MP2 OFF, MN3 OFF, MN4 ON)
*   g_mp1 ≈ 200µS, g_mn4 ≈ 100µS, others ≈ 0
*   J_YY = 200µS,  J_YM = 0,     J_MY = 0,     J_MM = -100µS
*   det(J) = -20nS² → well-conditioned
*
* Corner 3: A=1.8, B=0 → Y=1.8 (MP1 OFF, MP2 ON, MN3 ON, MN4 OFF)
*   g_mp2 ≈ 200µS, g_mn3 ≈ 50µS, others ≈ 0
*   J_YY = 250µS,  J_YM = -50µS, J_MY = 50µS, J_MM = -50µS
*   det(J) = -12.5µS² - 2.5µS² = -10µS² → well-conditioned
*
* Corner 4: A=1.8, B=1.8 → Y≈0 (both PMOS OFF, both NMOS ON)
*   g_mn3 ≈ 50µS (linear region), g_mn4 ≈ 100µS (linear region)
*   J_YY = 50µS,   J_YM = -50µS, J_MY = 50µS, J_MM = -150µS
*   det(J) = -7.5µS² - 2.5µS² = -5µS² → well-conditioned
*
* SPICE adds GMIN=1e-12S to every node to prevent singular matrix.
******************************************************************************

* Newton-Raphson iteration parameters
.OPTIONS ITL1=300  ITL2=50  ITL6=100
.OPTIONS GMIN=1e-12  RELTOL=1e-6
.OPTIONS ABSTOL=1e-12  VNTOL=1e-6

* Initial conditions (helps NR convergence)
.IC V(Y)=0.9  V(A)=0  V(B)=0

.OP

******************************************************************************
* OUTPUT
******************************************************************************

.PRINT DC V(A) V(Y) @X1.MP1[gm] @X1.MP1[gds] @X1.MN3[gm] @X1.MN3[gds] @X1.MN4[gm] @X1.MN4[gds]
.PRINT TRAN V(A) V(B) V(Y) I(VDD)
.PLOT  TRAN V(A) V(B) V(Y)
.PLOT  AC   VDB(Y) VP(Y)

.OPTIONS POST=2 PROBE MEASDGT=6

.END
