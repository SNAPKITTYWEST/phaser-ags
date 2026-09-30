******************************************************************************
* NAND GATE HIERARCHICAL BUILD — 4 gates from NAND primitives
* Demonstrates: NOT, AND, OR, XOR all built from NAND2 subcircuit
******************************************************************************

.INCLUDE nand2_cmos.sp

******************************************************************************
* NOT from NAND:  Y = NAND(A, A)
******************************************************************************
.SUBCKT INV A Y VDD GND
X1 A A Y VDD GND NAND2
.ENDS INV

******************************************************************************
* AND from NAND:  Y = NAND(NAND(A,B), NAND(A,B))
******************************************************************************
.SUBCKT AND2 A B Y VDD GND
XNAND A B N1 VDD GND NAND2
XINV  N1 N1 Y VDD GND INV
.ENDS AND2

******************************************************************************
* OR from NAND:  Y = NAND(NAND(A,A), NAND(B,B))
*   By De Morgan: (a'·b')' = a + b
******************************************************************************
.SUBCKT OR2 A B Y VDD GND
XNA A A NA VDD GND NAND2
XNB B B NB VDD GND NAND2
XOR NA NB Y VDD GND NAND2
.ENDS OR2

******************************************************************************
* XOR from NAND:  Y = NAND(NAND(A,NAND(A,B)), NAND(B,NAND(A,B)))
******************************************************************************
.SUBCKT XOR2 A B Y VDD GND
XN1 A  B  N  VDD GND NAND2
XN2 A  N  NA VDD GND NAND2
XN3 B  N  NB VDD GND NAND2
XN4 NA NB Y  VDD GND NAND2
.ENDS XOR2

******************************************************************************
* TESTBENCH: verify all 4 derived gates
******************************************************************************

VDD VDD 0 DC 1.8
VGND GND 0 DC 0

VA A 0 PULSE(0 1.8 5n 200p 200p 5n 20n)
VB B 0 PULSE(0 1.8 2.5n 200p 200p 2.5n 10n)

XI  A Y_INV   VDD GND INV
XA  A B Y_AND VDD GND AND2
XO  A B Y_OR  VDD GND OR2
XX  A B Y_XOR VDD GND XOR2

.TRAN 10p 40n
.PRINT TRAN V(A) V(B) V(Y_INV) V(Y_AND) V(Y_OR) V(Y_XOR)
.OPTIONS POST=2
.END
