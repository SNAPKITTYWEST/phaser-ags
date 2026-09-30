******************************************************************************
* 3-INPUT CMOS NAND GATE — Extended Jacobian (3×3 block)
* Shows how the Jacobian scales with more series NMOS devices
******************************************************************************

.MODEL nmos180 NMOS LEVEL=49
+ VTH0=0.42 U0=460 TOX=4.1N LMIN=0.18U SAT=1 PCLM=1.3 RDSW=190

.MODEL pmos180 PMOS LEVEL=49
+ VTH0=-0.42 U0=170 TOX=4.1N LMIN=0.18U SAT=1 PCLM=2.0 RDSW=420

******************************************************************************
* NAND3: 3 PMOS parallel, 3 NMOS series
*
*        VDD
*     ┌──┴──┬──┴──┬──┴──┐
*     P1    P2    P3        ← 3 PMOS in parallel
*     A┤    B┤    C┤
*     └──┬──┴──┬──┴──┬──┘
*        │
*        Y ──── Output
*        │
*     ┌──┴──┐
*     N1    │            ← NMOS series chain
*     A┤    │
*     └──┬──┘
*     ┌──┴──┐
*     N2    │
*     B┤    │
*     └──┬──┘
*     ┌──┴──┐
*     N3    │
*     C┤    │
*     └──┬──┘
*        │
*       GND
*
* Internal nodes: M1 (between N1-N2), M2 (between N2-N3)
* Jacobian is 3×3: {Y, M1, M2}
******************************************************************************

.SUBCKT NAND3 A B C Y VDD GND
MP1 Y A VDD VDD pmos180 W=600n L=180n
MP2 Y B VDD VDD pmos180 W=600n L=180n
MP3 Y C VDD VDD pmos180 W=600n L=180n

MN1 Y   A M1  GND nmos180 W=600n L=180n
MN2 M1  B M2  GND nmos180 W=600n L=180n
MN3 M2  C GND GND nmos180 W=600n L=180n

CM1 M1 GND 0.3f
CM2 M2 GND 0.3f
CLOAD Y GND 15f

.ENDS NAND3

******************************************************************************
* TESTBENCH
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

VA A 0 PULSE(0 1.8 5n 100p 100p 5n 30n)
VB B 0 PULSE(0 1.8 2.5n 100p 100p 2.5n 15n)
VC C 0 PULSE(0 1.8 1.25n 100p 100p 1.25n 7.5n)

X1 A B C Y VDD GND NAND3

******************************************************************************
* 3×3 JACOBIAN STRUCTURE
*
*     ┌                           ┐
*     │  J_YY    J_YM1   J_YM2   │
* J = │  J_M1Y   J_M1M1  J_M1M2  │
*     │  J_M2Y   J_M2M1  J_M2M2  │
*     └                           ┘
*
* J_YY   = g_mp1 + g_mp2 + g_mp3 + g_mn1_ds
* J_YM1  = -g_mn1_ds
* J_YM2  = 0
* J_M1Y  = g_mn1_ds
* J_M1M1 = -(g_mn1_ds + g_mn2_ds)
* J_M1M2 = -g_mn2_ds
* J_M2Y  = 0
* J_M2M1 = g_mn2_ds
* J_M2M2 = -(g_mn2_ds + g_mn3_ds)
*
* This is a TRIDIAGONAL matrix — typical for series NMOS chains.
* SPICE exploits this sparse structure for efficient LU factorization.
******************************************************************************

.DC VA 0 1.8 0.01
.TRAN 1p 60n
.AC DEC 20 1 100G

.SAVE @X1.MP1[gm] @X1.MP1[gds] @X1.MN1[gm] @X1.MN1[gds]
.SAVE @X1.MN2[gm] @X1.MN2[gds] @X1.MN3[gm] @X1.MN3[gds]

.MEASURE TRAN tpHL TRIG V(A) VAL=0.9 RISE=1 TARG V(Y) VAL=0.9 FALL=1
.MEASURE TRAN tpLH TRIG V(C) VAL=0.9 FALL=1 TARG V(Y) VAL=0.9 RISE=1
.MEASURE TRAN Pavg AVG POWER FROM=0 TO=60n

.IC V(Y)=0.9 V(M1)=0.6 V(M2)=0.3
.OPTIONS POST=2 GMIN=1e-12 ITL1=300

.END
