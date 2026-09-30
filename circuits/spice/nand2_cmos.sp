******************************************************************************
* CMOS NAND GATE — Transistor-Level SPICE Netlist
* 180nm CMOS process (BSIM3v3 models)
* 2-input NAND with 4 transistors (2 PMOS parallel, 2 NMOS series)
******************************************************************************

* ---- Process Models (180nm BSIM3v3) ----
.MODEL nmos180 NMOS LEVEL=49
+ LMIN=0.18U  WMIN=0.22U
+ VTH0=0.42   TOX=4.1N
+ U0=460      K1=0.55
+ SAT=1       DSUB=0.8
+ PCLM=1.3    PDIBLC1=0.012
+ RDSW=190    PRWB=0.12
+ CGSO=2.1N   CGDO=2.1N   CGBO=0.8N
+ CJ=1.0M     CJSW=0.22M  MJ=0.36  MJSW=0.12
+ PB=0.9      PBSW=0.9

.MODEL pmos180 PMOS LEVEL=49
+ LMIN=0.18U  WMIN=0.22U
+ VTH0=-0.42  TOX=4.1N
+ U0=170      K1=0.58
+ SAT=1       DSUB=1.0
+ PCLM=2.0    PDIBLC1=0.008
+ RDSW=420    PRWB=-0.05
+ CGSO=2.1N   CGDO=2.1N   CGBO=0.8N
+ CJ=1.2M     CJSW=0.28M  MJ=0.42  MJSW=0.18
+ PB=0.9      PBSW=0.9

******************************************************************************
* SUBCIRCUIT: 2-input CMOS NAND gate
* .SUBCKT NAND2 A B Y VDD GND
*
*   Pull-up network: PMOS in parallel
*     M1: PMOS A → VDD-Y
*     M2: PMOS B → VDD-Y
*
*   Pull-down network: NMOS in series
*     M3: NMOS A → Y-mid
*     M4: NMOS B → mid-GND
*
*   Sizing for balanced delays (180nm):
*     NMOS: W=400n (2× minimum, compensates series)
*     PMOS: W=400n (balanced with sized NMOS)
******************************************************************************

.SUBCKT NAND2 A B Y VDD GND
* Pull-up: PMOS in parallel
MP1 Y A VDD VDD pmos180 W=400n L=180n
MP2 Y B VDD VDD pmos180 W=400n L=180n

* Pull-down: NMOS in series
MN3 Y   A MID  GND nmos180 W=400n L=180n
MN4 MID B GND  GND nmos180 W=400n L=180n

* Internal node capacitance (mid-point of NMOS stack)
CMID MID GND 0.5f

* Output load capacitance
CLOAD Y GND 10f

.ENDS NAND2

******************************************************************************
* TESTBENCH
******************************************************************************

* Global supplies
VDD VDD 0 DC 1.8
VGND GND 0 DC 0

* Input stimuli — all 4 combinations
VA A 0 PULSE(0 1.8 5n 200p 200p 5n 20n)
VB B 0 PULSE(0 1.8 2.5n 200p 200p 2.5n 10n)

* Instantiate NAND gate
X1 A B Y VDD GND NAND2

******************************************************************************
* ANALYSIS COMMANDS
******************************************************************************

* Transient analysis
.TRAN 10p 40n

* DC sweep for transfer characteristics
.DC VA 0 1.8 0.01 VB 0 1.8 0.9

* Measure propagation delay (A rising, B=1.8)
.MEASURE TRAN tpLH TRIG V(A) VAL=0.9 RISE=1 TARG V(Y) VAL=0.9 FALL=1
.MEASURE TRAN tpHL TRIG V(A) VAL=0.9 RISE=1 TARG V(Y) VAL=0.9 FALL=1

* Measure rise/fall times
.MEASURE TRAN t_rise TRIG V(Y) VAL=0.18 RISE=1 TARG V(Y) VAL=1.62 RISE=1
.MEASURE TRAN t_fall TRIG V(Y) VAL=1.62 FALL=1 TARG V(Y) VAL=0.18 FALL=1

* Measure static power (should be ~0 for CMOS)
.MEASURE TRAN avg_power AVG POWER FROM=1n TO=40n

* Measure peak current during switching
.MEASURE TRAN peak_current MAX I(VDD) FROM=1n TO=40n

* AC analysis for frequency response
.AC DEC 10 1k 100G

******************************************************************************
* OUTPUT
******************************************************************************
.PRINT TRAN V(A) V(B) V(Y)
.PLOT  TRAN V(A) V(B) V(Y)

.OPTIONS POST=2 PROBE MEASDGT=5
.END
