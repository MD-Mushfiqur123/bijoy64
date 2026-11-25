# BIJOY-64 — a custom 64-bit CPU, from scratch

BIJOY-64 (বিজয় = victory) is a **from-scratch 64-bit RISC CPU** with its own
custom ISA (not RISC-V, not MIPS, not anyone else's), written in **Verilog**.

```
┌────────────────────────────────────────────────────────────────┐
│  docs/ISA.md     — the instruction set specification           │
│  tools/          — assembler + golden-model simulator          │
│  rtl/            — 5-stage pipelined core (Verilog)            │
│  tb/             — simulation testbench                        │
│  tests/          — assembly test programs + EXPECT checks      │
└────────────────────────────────────────────────────────────────┘
```

## Architecture at a glance

| Property          | BIJOY-64                                        |
|-------------------|-------------------------------------------------|
| Datapath          | 64-bit                                          |
| Instruction width | 32-bit fixed                                    |
| Registers         | 16 × 64-bit GPRs, `r0` = hardwired zero         |
| ISA               | Custom: load/store, 3 ALU formats + MUL/DIV/REM |
| Pipeline          | 5 stages: IF → ID → EX → MEM → WB               |
| Forwarding        | EX/MEM→EX, MEM/WB→EX (full)                     |
| Hazards           | load-use: 1-cycle bubble                        |
| Control flow      | resolved in EX; dynamic prediction (64-entry BTB + 2-bit counters), mispredict repair |
| Instructions      | ADD SUB AND OR XOR SLL SRL SRA SLT SLTU MUL DIV REM, ADDI ANDI ORI XORI SLLI SRLI SRAI SLTI SLTIU LODI, LD, ST, BEQ BNE BLT BGE BLTU BGEU, JAL JALR, HLT |

Full spec: **[docs/ISA.md](docs/ISA.md)** (hand-designed encodings, layouts and
semantics — see also the pipeline contract there).

## Layout

```
rtl/alu64.v           64-bit ALU (13 ops incl. signed MUL/DIV/REM, /0 defined)
rtl/regfile16x64.v    16 x 64-bit register file, r0 = 0, combinational read
rtl/decoder.v         full instruction decode -> control signals
rtl/bpu.v             dynamic branch predictor: 64-entry BTB + 2-bit counters
rtl/bijoy64_core.v    the pipelined core: stages, forwarding, hazard, flush
rtl/imem.v            16 KB instruction memory ($readmemh)
rtl/dmem.v            4 KB data memory (byte-addressed, word-aligned, 64-bit)
rtl/bijoy64_top.v     top-level wiring
tb/tb_core.v          Icarus-Verilog testbench: run to halt, dump arch state
tools/assembler.py    .asm -> imem.hex / dmem.hex (labels, LI/J/RET/NOP pseudo-ops)
tools/golden.py       architectural golden model in Python
tools/pp_shim.py      tiny `iverilog -E` stand-in for pyverilog linting
tests/run_tests.py    assemble + golden-execute + EXPECT-diff + Verilog parse
```

## Running

### Verify the design (works anywhere with Python 3)

```bash
python3 tests/run_tests.py
```

This assembles every test in `tests/`, executes it on the golden model and
checks every `# EXPECT rX = ...` / `# EXPECT mem[0x..] = ...` line, plus
pyverilog-parses the whole RTL. Current status: **5/5 tests pass**.

### RTL simulation (requires Icarus Verilog)

```bash
make test              # also produces build/<test>/imem.hex + dmem.hex
make sim T=t05_hazard  # iverilog build + run; prints final architectural state
```

The sandbox this project was authored in has no Verilog simulator binary
(packages can't install here), so RTL was verified with the pyverilog syntax
gate plus the golden model; running `make sim T=...` on a normal machine with
iverilog is the last-mile check for each test.

### Assemble your own program

```bash
python3 tools/assembler.py myprog.asm --dump
python3 tools/golden.py myprog.asm --regs --mem
```

Example program:

```asm
    LODI    r1, 10
    LODI    r2, 0
loop:
    ADD     r2, r2, r1
    ADDI    r1, r1, -1
    BNE     r1, r0, loop
    HLT
```

## The long road (dream plan)

The full multi-phase plan — compiler fork, privilege/MMU, caches,
out-of-order core, applications — lives in
**[docs/ROADMAP.md](docs/ROADMAP.md)**.

Current position:

- ✅ **Phase 0** — custom ISA + pipelined core + toolchain (merged)
- 🚧 **Phase 1** —
  [x] dynamic branch predictor (BTB + 2-bit counters),
  [ ] multi-cycle DIV, [ ] cycle-counting tb, [ ] FPGA bring-up kit
- ⏭ **Phase 2** — C compiler decision fork (compat sub-mode vs LLVM backend)

Each phase keeps the golden model synced first, RTL second — the assembler and
test suite are the backbone of that contract.
