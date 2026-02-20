// Multiplies R0 and R1 and stores the result in R2.
// (R0, R1, R2 refer to RAM[0], RAM[1], and RAM[2], respectively.)
// The algorithm is based on repetitive addition.

// Store R0 in a
@R0 // A = R0
D=M // M = Ram[R0]
@a  // A = a (at 16th word from the beginning of RAM)
M=D // ram[a] = ram[r0]
// Store R1 in b
@R1
D=M
@b
M=D

@R2
M=0

(LOOP)
// if b == 0; EXIT the loop
@b
D=M
@END
D;JEQ
// add a to R2
@a
D=M
@R2
M=D+M
// dec b
@b 
M=M-1
D=M
@LOOP
D;JNE

(END)
@END
0;JMP