# ZAP — CPU Design Documentation

## Table of Contents

1. [Overview](#overview)
2. [Instruction Set Architecture](#instruction-set-architecture)
3. [CPU Internal Components](#cpu-internal-components)
4. [Data Flow Diagram](#data-flow-diagram)
5. [Instruction Decoding](#instruction-decoding)
6. [Component Deep Dive](#component-deep-dive)
7. [Jump Logic](#jump-logic)
8. [Timing: Combinational vs Clocked](#timing-combinational-vs-clocked)
9. [The Full Computer](#the-full-computer)

---

## Overview

The ZAP CPU is a **16-bit processor** built entirely from scratch. It
follows a **Harvard style** memory layout with separate instruction and data
memory, executes one instruction per clock cycle, and supports two
instruction formats: **A-instructions** and **C-instructions**.

The CPU contains five core components:

- **A Register**: holds addresses and constants
- **D Register**: holds data for computation
- **ALU**: performs arithmetic and logic operations
- **Program Counter (PC)**: tracks the next instruction address
- **Instruction Decoder**: routes control signals from the instruction bits

---

## Instruction Set Architecture

### A-Instruction (Address / Constant)

Used to load a 15-bit value into the A register.

MSB, opcode = 0 (A-instruction)

| Field | Bits | Purpose |
|-------|------|---------|
| `opcode = 0` | `[15]` | Tells that this is A instruction |

**Example:** `@12345` → `0011000000111001`

### C-Instruction (Compute)

Used to perform an ALU operation, store the result, and optionally jump.

MSB, opcode = 1 (C-instruction)

| Field | Bits | Purpose |
|-------|------|---------|
| `opcode = 1` | `[15]` | Tells that this is C instruction |
| `a` | `[12]` | ALU input selector: A register or Memory |
| `comp` | `[11..6]` | ALU control: `zx, nx, zy, ny, f, no` |
| `dest` | `[5..3]` | Write destination: `d1`=A, `d2`=D, `d3`=M |
| `jump` | `[2..0]` | Jump condition: `j1`=neg, `j2`=zero, `j3`=pos |

**Example:** `D=A-D` → `1110000111010000`

---

## CPU Internal Components

Instead of ASCII use mermaid to draw suchh diagrams (and use bright colors)
```text
┌─────────────────────────────────────────────────────────────────────┐
│                              CPU                                    │
│                                                                     │
│  instruction[16] ──→ [INSTRUCTION DECODER] ──→ control signals      │
│                              │                                      │
│                         ┌────┴─────────────────────────┐            │
│                         ↓                              ↓            │
│                    ┌─────────┐                    ┌─────────┐       │
│  instruction ─────→│         │                    │         │       │
│              Mux16→│ A Reg   │──┬────────────────→│         │       │
│  aluOut ──────────→│         │  │                 │  ALU    │──→ outM
│                    └─────────┘  │   ┌────────────→│         │       │
│                         │       │   │             └────┬────┘       │
│                    addressM     │   │                  │            │
│                                 │   │                  │            │
│                         ┌───────┘   │             ┌────┴────┐       │
│                         ↓           │             │         │       │
│                    ┌─────────┐      │             │ aluOut  │       │
│                    │  Mux16  │      │             │         │       │
│         inM ──────→│ (A / M) │──────┘             └────┬────┘       │
│                    └─────────┘                         │            │
│                                                        ↓            │
│                                                   ┌─────────┐       │
│                                                   │  D Reg  │       │
│                                                   └────┬────┘       │
│                                                        │            │
│                                                        └──→ ALU.x   │
│                                                                     │
│                    ┌─────────┐                                      │
│       aOut ───────→│   PC    │──────────────────────────────→ pc    │
│       doJump ─────→│         │                                      │
│       reset ──────→│         │                                      │
│                    └─────────┘                                      │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Diagram

Below is the **cycle-by-cycle data flow** showing how an instruction
is fetched, decoded, executed, and the result stored:

```text
              ┌──────────────────────────────────────────────┐
              │                                              │
              ↓                                              │
         ┌─────────┐    instruction    ┌─────────────────┐   │
         │ ROM32K  │ ────────────────→ │       CPU       │   │
         └─────────┘                   │                 │   │
              ↑                        │  [Decode]       │   │
              │                        │     │           │   │
           pc │                        │     ↓           │   │
              │                        │  [ALU Compute]  │   │
              │                        │     │           │   │
              │                        │     ↓           │   │
              │                        │  [Store Result] │   │
              │                        │     │           │   │
              │                        └─────┼───────────┘   │
              │                              │               │
              └──────────────────────────────┘               │
                                                             │
                    outM, writeM, addressM                    │
                         │                                   │
                         ↓                                   │
                    ┌─────────┐     inM                      │
                    │ Memory  │ ─────────────────────────────┘
                    └─────────┘
```

### Step-by-step execution of a single cycle

```text
Step 1: PC outputs address         →  ROM32K fetches instruction
Step 2: Instruction enters CPU     →  Decoder extracts control signals
Step 3: A/M Mux selects ALU input  →  ALU computes result
Step 4: Result routes to dest      →  A, D, or M gets written
Step 5: Jump logic evaluates       →  PC loads jump target or increments
Step 6: Clock edge commits         →  Registers latch new values
```

---

## Instruction Decoding

The instruction decoder is not a single chip — it is **implicit in the
wiring**. The instruction bits directly control the datapath:

```text
instruction[15]    ──→ isC (C-instruction flag)
instruction[12]    ──→ Mux16 sel (A vs M into ALU)
instruction[11..6] ──→ ALU control pins (zx, nx, zy, ny, f, no)
instruction[5]     ──→ d1: write to A register
instruction[4]     ──→ d2: write to D register
instruction[3]     ──→ d3: write to Memory (writeM)
instruction[2]     ──→ j1: jump if ALU output < 0
instruction[1]     ──→ j2: jump if ALU output = 0
instruction[0]     ──→ j3: jump if ALU output > 0
```

**Key gating rule:** All C-instruction control signals are AND-gated with
`instruction[15]`. This ensures that during an A-instruction, no
unintended writes or jumps occur.

```text
                  instruction[15]
                       │
          ┌────────────┼────────────┐
          │            │            │
          ↓            ↓            ↓
     ┌─────────┐ ┌─────────┐ ┌─────────┐
     │  AND    │ │  AND    │ │  AND    │
     │ d1&isC  │ │ d2&isC  │ │ d3&isC  │
     └────┬────┘ └────┬────┘ └────┬────┘
          │            │            │
          ↓            ↓            ↓
       loadA        loadD        writeM
```

---

## Component Deep Dive

### A Register

**Purpose:** Holds either a constant/address (from A-instruction) or
an ALU result (from C-instruction with `d1=1`).

**Input selection:**

| Condition | Source | Mux sel |
|-----------|--------|---------|
| A-instruction (`instruction[15]=0`) | `instruction[0..15]` | 0 |
| C-instruction writing to A (`d1=1`) | ALU output | 1 |

**Load condition:**

```text
loadA = isAinstruction OR (isCinstruction AND instruction[5])
```

**Outputs:**
- `addressM[15]` — sent directly to data memory as address
- `aOut[16]` — fed to ALU Mux and PC for potential jumps

---

### D Register

**Purpose:** General-purpose data register. Only receives input from
the ALU output.

**Load condition:**

```text
loadD = isCinstruction AND instruction[4]
```

**Output:**
- `dOut[16]` — always wired to ALU input `x`

---

### ALU (Arithmetic Logic Unit)

**Purpose:** Performs all computation. Takes two 16-bit inputs and
produces a 16-bit output based on six control bits.

**Inputs:**

| Input | Source |
|-------|--------|
| `x` | D register (`dOut`) |
| `y` | Mux output: A register or Memory (`aOut` or `inM`) |

**Control bits** (from `instruction[11..6]`):

| Bit | Name | Effect |
|-----|------|--------|
| `instruction[11]` | `zx` | Zero the x input |
| `instruction[10]` | `nx` | Negate the x input |
| `instruction[9]` | `zy` | Zero the y input |
| `instruction[8]` | `ny` | Negate the y input |
| `instruction[7]` | `f` | 1 = Add, 0 = And |
| `instruction[6]` | `no` | Negate the output |

**Status outputs:**

| Output | Meaning |
|--------|---------|
| `zr` | Result is zero |
| `ng` | Result is negative (bit[15] = 1) |

These status flags drive the jump logic.

---

### Program Counter (PC)

**Purpose:** Tracks the address of the next instruction to execute.

**Behavior (priority order):**

| Condition | Action |
|-----------|--------|
| `reset = 1` | `PC = 0` (restart program) |
| `doJump = 1` | `PC = aOut` (jump to address in A) |
| Otherwise | `PC = PC + 1` (next instruction) |

```text
         aOut ──────→ ┌────────┐
         doJump ────→ │   PC   │ ──→ pc[15]
         reset ─────→ │        │
         inc=true ──→ └────────┘
```

---

## Jump Logic

The jump evaluator determines whether the CPU should jump based on
the ALU output status and the jump bits in the instruction.

### Truth table

| j1 (neg) | j2 (zero) | j3 (pos) | Mnemonic | Jump when |
|----------|-----------|----------|----------|-----------|
| 0 | 0 | 0 | — | Never |
| 0 | 0 | 1 | JGT | `out > 0` |
| 0 | 1 | 0 | JEQ | `out = 0` |
| 0 | 1 | 1 | JGE | `out ≥ 0` |
| 1 | 0 | 0 | JLT | `out < 0` |
| 1 | 0 | 1 | JNE | `out ≠ 0` |
| 1 | 1 | 0 | JLE | `out ≤ 0` |
| 1 | 1 | 1 | JMP | Always |

### Logic implementation

```text
                ALU status flags
                 │          │
                 ↓          ↓
                ng         zr
                 │          │
         ┌───────┤    ┌─────┤
         ↓       │    ↓     │
    ┌─────────┐  │  ┌─────────┐
    │ AND     │  │  │ AND     │
    │ j1 & ng │  │  │ j2 & zr │
    └────┬────┘  │  └────┬────┘
         │       │       │
         │  ┌────┴──┐    │       ┌──────────────┐
         │  │ NOT   │    │       │  NOT(ng)     │
         │  └───┬───┘    │       │  AND         │
         │      │        │       │  NOT(zr)     │
         │      │   ┌────┴──┐   │  = isPositive│
         │      │   │ NOT   │   └──────┬───────┘
         │      │   └───┬───┘          │
         │      │       │         ┌─────────┐
         │      │       │         │ AND     │
         │      │       │         │j3 & pos │
         │      │       │         └────┬────┘
         │      │       │              │
         ↓      ↓       ↓              ↓
        ┌────────────────────────────────┐
        │     OR (any condition true?)   │
        └───────────────┬────────────────┘
                        │
                        ↓
                   ┌─────────┐
                   │  AND    │
                   │ & isC   │ ←── gate: only jump on C-instructions
                   └────┬────┘
                        │
                        ↓
                     doJump ──→ PC.load
```

---

## Timing: Combinational vs Clocked

Understanding the timing model is critical for correct CPU operation.

### Combinational outputs

These change **immediately** when inputs change — no clock needed.

| Output | Source |
|--------|--------|
| `outM` | Direct ALU output wire |
| `writeM` | `instruction[15] AND instruction[3]` |

### Clocked outputs

These **commit on the clock edge** — they hold their previous value
until the clock ticks.

| Output | Source |
|--------|--------|
| `addressM` | A register output |
| `pc` | Program Counter output |

### Timing diagram

```text
Clock:       __|‾‾‾‾‾|_____|‾‾‾‾‾|_____|‾‾‾‾‾|_____
                 cyc N       cyc N+1     cyc N+2

             ┌─────────── combinational ───────────┐
outM:        │  computed from current instruction   │
writeM:      │  derived from current instruction    │
             └──────────────────────────────────────┘

             ┌──────────── clocked (sequential) ───┐
addressM:    │  value from A reg set LAST cycle     │
pc:          │  value from PC set LAST cycle        │
             └──────────────────────────────────────┘

Within a single cycle:
  tick (rising edge): inputs are read, combinational logic settles
  tock (falling edge): registers latch new values
```

---

## The Full Computer

The Computer chip connects three major components with simple wiring:

```text
┌──────────────────────────────────────────────────────────────────┐
│                          COMPUTER                                │
│                                                                  │
│   reset ──────────────────────────────────────┐                  │
│                                               │                  │
│        ┌──────────┐   instruction[16]   ┌─────┴──────┐          │
│        │          │ ──────────────────→ │            │          │
│        │  ROM32K  │                     │    CPU     │          │
│        │          │ ←────────────────── │            │          │
│        └──────────┘     pc[15]          │            │          │
│                                         │            │          │
│                                         │            │          │
│        ┌──────────┐     inM[16]         │            │          │
│        │          │ ──────────────────→ │            │          │
│        │  Memory  │ ←────────────────── │            │          │
│        │          │     outM[16]        │            │          │
│        │ (RAM16K  │ ←────────────────── │            │          │
│        │  Screen  │     writeM          │            │          │
│        │  Kbd)    │ ←────────────────── │            │          │
│        │          │     addressM[15]    │            │          │
│        └──────────┘                     └────────────┘          │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

### Connection Table

| Signal | From | To | Width | Description |
|--------|------|----|-------|-------------|
| `pc` | CPU | ROM32K | 15 bits | Address of next instruction |
| `instruction` | ROM32K | CPU | 16 bits | Current instruction to execute |
| `inM` | Memory | CPU | 16 bits | Data read from RAM[A] |
| `outM` | CPU | Memory | 16 bits | Data to write to RAM[A] |
| `writeM` | CPU | Memory | 1 bit | Write enable signal |
| `addressM` | CPU | Memory | 15 bits | Target RAM address |
| `reset` | External | CPU | 1 bit | Restart program execution |

### Memory Map

| Address Range | Hex Range | Component | Size |
|---------------|-----------|-----------|------|
| `0–16383` | `0x0000–0x3FFF` | RAM16K | 16K words |
| `16384–24575` | `0x4000–0x5FFF` | Screen | 8K words |
| `24576` | `0x6000` | Keyboard | 1 word |

### Boot Sequence

```text
1. Set reset = 1     →  PC resets to 0
2. Set reset = 0     →  CPU begins fetch-execute cycle
3. ROM32K[0]         →  First instruction is fetched
4. CPU executes      →  Decode → Compute → Store → Next
5. Repeat forever    →  Until reset or power off
```

### Execution Cycle (Fetch-Execute)

```text
┌─────────────────────────────────────────────────┐
│                                                 │
│  ┌─────────┐    ┌─────────┐    ┌─────────┐     │
│  │  FETCH  │ →  │ DECODE  │ →  │ EXECUTE │     │
│  │         │    │         │    │         │     │
│  │ ROM[PC] │    │ Extract │    │ ALU op  │     │
│  │ → instr │    │ control │    │ Store   │     │
│  │         │    │ signals │    │ Jump?   │     │
│  └─────────┘    └─────────┘    └────┬────┘     │
│                                     │          │
│                                     ↓          │
│                                ┌─────────┐     │
│                                │  COMMIT │     │
│                                │         │     │
│                                │ Regs    │     │
│                                │ latch   │     │
│                                │ on edge │     │
│                                └────┬────┘     │
│                                     │          │
│                                     └──────────┘
└─────────────────────────────────────────────────┘
```

---

## Summary

The ZAP CPU achieves computation through elegant simplicity:

- **2 registers** (A and D) hold all working data
- **1 ALU** performs all arithmetic and logic
- **1 PC** manages control flow
- **Instruction bits wire directly** to control signals — no microcode

Every component was built from NAND gates upward:

```text
NAND → NOT, AND, OR → Mux, DMux → Adder → ALU
NAND → DFF → Bit → Register → RAM → Memory
NAND → ... → CPU → Computer
```

From a single logic gate to a programmable computer.