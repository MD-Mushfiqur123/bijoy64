# MX-Hpi-1 — Custom 64-bit Instruction Set Architecture (ISA)

MX-Hpi-1 is a from-scratch, load/store RISC architecture with a **64-bit datapath**
and **32-bit fixed-width instructions**, designed for a classical 5-stage pipeline
(IF → ID → EX → MEM → WB) with forwarding, hazard stall and static branch
predict-not-taken. It is *not* derived from any existing ISA — every opcode and
encoding below is custom.

## 1. Programmer-visible state

| State          | Size     | Notes                                    |
|----------------|----------|------------------------------------------|
| `r0` … `r15`   | 64-bit   | 16 GPRs. **`r0` is hardwired to 0** (writes ignored). |
| `pc`           | 64-bit   | Byte-addressed; instructions are 4-byte aligned. |
| Memory         | byte addr| 64-bit word accesses only, naturally aligned (`addr[2:0] = 000`). |

Calling convention (chosen, enforced by the assembler pseudo-instructions):

| Reg  | Role                  |
|------|-----------------------|
| r1–r10 | arguments / scratch |
| r11–r14 | callee-saved values |
| r15 | link register (`RET` = jump to r15) |

## 2. Instruction layouts (32-bit words)

```
31    26 25  22 21  18 17  14 13 11 10    4 3 0
+-------+-----+-----+-----+-----+--------+-----+
|  op   | rd  | rs1 | rs2 |f3   | f7     | rsv |   R-type
+-------+-----+-----+-----+-----+--------+-----+

I-type  : op[31:26] rd[25:22] rs1[21:18] imm18[17:0]  (signed)
S-type  : op[31:26] --[25:22] rs1[21:18] rs2[17:14] imm12[13:2] 00[1:0] (signed)
B-type  : same field geometry as S-type; target = pc + (sext(imm12) << 2)
J-type  : op[31:26] rd[25:22] off22[21:0] (signed; target = pc + (off22 << 2))
```

`rs1`/`rs2` name a *source register number* (4 bits, 0–15). Immediates are
stored two's-complement as drawn above.

## 3. Opcodes (6-bit field `op`)

### R-type — arithmetic / logic on 64-bit values

| op    | insn  | semantics (rd ← f(rs1, rs2))                  |
|-------|-------|-----------------------------------------------|
| 0x01  | ADD   | rs1 + rs2                                     |
| 0x02  | SUB   | rs1 − rs2                                     |
| 0x03  | AND   | rs1 & rs2                                     |
| 0x04  | OR    | rs1 \| rs2                                    |
| 0x05  | XOR   | rs1 ^ rs2                                     |
| 0x06  | SLL   | rs1 << rs2[5:0]                               |
| 0x07  | SRL   | rs1 >> rs2[5:0] (logical)                     |
| 0x08  | SRA   | rs1 >> rs2[5:0] (arithmetic)                  |
| 0x09  | SLT   | rs1 < rs2 signed                       → 0/1  |
| 0x0A  | SLTU  | rs1 < rs2 unsigned                     → 0/1  |
| 0x0B  | MUL   | low 64 bits of rs1 × rs2                      |
| 0x0C  | DIV   | rs1 ÷ rs2 signed; rs2 = 0 → result 0          |
| 0x0D  | REM   | rs1 mod rs2 signed; rs2 = 0 → result = rs1    |

### I-type — immediate operations (`imm` = sext(18-bit))

| op    | insn  | semantics                                     |
|-------|-------|-----------------------------------------------|
| 0x10  | ADDI  | rd ← rs1 + sext(imm18)                        |
| 0x11  | ANDI  | rd ← rs1 & sext(imm18)                        |
| 0x12  | ORI   | rd ← rs1 \| zext(imm18)                       |
| 0x13  | XORI  | rd ← rs1 ^ sext(imm18)                        |
| 0x14  | SLLI  | rd ← rs1 << imm[5:0]                          |
| 0x15  | SRLI  | rd ← rs1 >> imm[5:0] (logical)                |
| 0x16  | SRAI  | rd ← rs1 >> imm[5:0] (arithmetic)             |
| 0x17  | SLTI  | rd ← (rs1 < sext(imm18)) signed        → 0/1  |
| 0x18  | SLTIU | rd ← (rs1 <u sext(imm18)) unsigned     → 0/1  |
| 0x19  | LODI  | rd ← zext(imm18)   (`rs1` ignored)            |
| 0x1A  | LD    | rd ← Mem64[rs1 + sext(imm18)]                 |

### S-type — store

| op    | insn  | semantics                                     |
|-------|-------|-----------------------------------------------|
| 0x20  | ST    | Mem64[rs1 + sext(imm12)] ← rs2                |

### B-type — conditional branches on registers

| op    | insn  | condition (taken → pc ← pc + imm12<<2)        |
|-------|-------|-----------------------------------------------|
| 0x30  | BEQ   | rs1 == rs2                                    |
| 0x31  | BNE   | rs1 != rs2                                    |
| 0x32  | BLT   | rs1 <  rs2 (signed)                           |
| 0x33  | BGE   | rs1 >= rs2 (signed)                           |
| 0x34  | BLTU  | rs1 <  rs2 (unsigned)                         |
| 0x35  | BGEU  | rs1 >= rs2 (unsigned)                         |

### J-family

| op    | insn  | semantics                                     |
|-------|-------|-----------------------------------------------|
| 0x3D  | JALR  | rd ← pc+4; pc ← rs1 + sext(imm18)             |
| 0x3E  | JAL   | rd ← pc+4; pc ← pc + sext(off22)<<2           |

### System

| op    | insn  | semantics                                     |
|-------|-------|-----------------------------------------------|
| 0x00  | HLT   | halt the pipeline (simulation stop)           |

## 4. Pseudo-instructions (assembler-level, expand to real insns)

| Pseudo            | Expansion                                                             |
|-------------------|-----------------------------------------------------------------------|
| `NOP`             | `ADDI r0, r0, 0`                                                      |
| `LI rD, imm64`    | `LODI/SLLI/ORI` chain (r0 unused as source) — see §5                  |
| `J label`         | `JAL r0, label`                                                       |
| `RET`             | `JALR r0, 0(r15)`                                                     |

## 5. 64-bit constants via `LI` (LODI64)

`imm64 = c3<<54 | c2<<36 | c1<<18 | c0` with 18-bit chunks; assembler emits:

```
LODI  rd, c3
SLLI  rd, rd, 18
ORI   rd, rd, c2
SLLI  rd, rd, 18
ORI   rd, rd, c1
SLLI  rd, rd, 18
ORI   rd, rd, c0
```

(7 instructions, no scratch register required.)

## 6. Pipeline contract (hardware reference)

- 5 stages: IF, ID, EX, MEM, WB.
- **Forwarding:** EX/MEM → EX, MEM/WB → EX (priority to the younger result);
  MEM/WB → MEM fixes store-data hazards.
- **Load-use hazard:** one-cycle bubble (ID/EX is flushed and IF/ID stalls).
- **Branches/JAL/JALR:** resolved in EX; when taken, IF/ID and ID/EX are
  flushed and IF is redirected (2-cycle mis-predict cost; static predict-not-taken).
- **HLT:** when HLT reaches EX the core stops fetching; younger instructions in
  flight are flushed; the pipe drains and the core raises `halted`.
