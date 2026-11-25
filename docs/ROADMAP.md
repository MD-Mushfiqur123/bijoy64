# BIJOY-64 — The Long Road (Master Plan)

> একটা স্বপ্ন: scratch থেকে custom 64-bit CPU — শেষ পর্যন্ত OS-যোগ্য, compiler-চালিত,
> modern (out-of-order) hardware। এই document-টা পুরো সিঁড়ির ম্যাপ।

Status marker: **[DONE] / [ACTIVE] / [NEXT] / [FUTURE]**

---

## Phase 0 — Foundation  **[DONE]**
- Custom 64-bit ISA (16 GPRs, fixed 32-bit insn, custom encoding) — `docs/ISA.md`
- 5-stage pipeline (IF ID EX MEM WB), full forwarding, load-use stall,
  control-flow resolved in EX with flush
- Assembler (labels, LI/J/RET pseudo-ops) + golden model + 5 test programs
- Icarus testbench, pyverilog syntax gate

## Phase 1 — Pipeline maturity  **[ACTIVE]**
Goal: *modern-CPU front-end ভিত*।
- [x] [2a] Dynamic branch predictor: 64-entry BTB + 2-bit saturating counters
      (`rtl/bpu.v`), IF-stage prediction, EX-stage mispredict repair + update
- [x] [2b] Multi-cycle DIV/REM unit (`rtl/div64.v`, 64-iteration restoring
      divider) + EX busy/stall handshake — the pipeline freezes around long
      divisions instead of blocking for a full clock period
- [x] [2c] Cycle accounting: live CPI in tb_core (iverilog: cycles/retired/CPI)
      + golden-model estimator (`golden.py --cycles`, full BTB/penalty replay,
      hand-verified against t02..t06)
- [ ] [2d] FPGA bring-up kit: PLL, reset synchronizer, UART (TX/RX), top module
      for Arty A7 / iCE40 — *first physical run: "Hello World" over UART*

**Acceptance:** program output over UART on real FPGA; CPI improved for
t04-style loops; all golden tests still pass (uarch changes must never break
the architectural contract).

## Phase 2 — C compiler decision fork  **[NEXT]**
Goal: *compile, not assemble*।
- Path A (recommended): **compat sub-mode** — RV64IMA encoding support behind
  a mode bit; unlocks the whole GCC/LLVM/binutils/Linux ecosystem for free.
- Path B (purist): BIJOY-64 LLVM backend (TableGen, RegisterInfo, CallingConv)
  — the "proper" long route, ~3-6+ months.
- Either way: define the ABI (calling convention, stack layout) formally in
  `docs/ABI.md`; assembler gets relocation/linking support.

**Acceptance:** a compiled C program (hello world → printf → malloc) runs on
both golden model and RTL.

## Phase 3 — Machine privilege + OS hooks  **[FUTURE]**
Goal: *OS-able machine state*।
- Privilege modes (M/S/U), CSR bank (mstatus, mtvec, mepc, satp, ...)
- Traps: timer + UART interrupts, syscall.ecall path, precise return (mret/sret)
- Physical memory protection first; MMU later
- Boot ROM + linkable loader

**Acceptance:** a small RTOS (FreeRTOS-style) boots; timer tick drives a
preemptive scheduler.

## Phase 4 — Memory hierarchy  **[FUTURE]**
- L1 I$/D$ (16-32 KB each, split), AXI/AHB-style bus, simple DRAM controller
  wrapper (target board BRAM first)
- MMU: TLB + Sv39-style 3-level page tables

**Acceptance:** cache hit-rate reporting in simulation; page-table walk
verified against a golden TLB model.

## Phase 5 — Out-of-order core ("Zen-এর মস্তিষ্ক")  **[FUTURE]**
- Register renaming (16 arch / 64+ phys), in-order dispatch, out-of-order EX
- Reservation stations, reorder buffer (precise state), load/store queue with
  disambiguation
- Progressive: OoO behind the same architectural interface — the golden model
  gates everything

**Acceptance:** identical arch results vs golden on randomized instruction
streams (fuzzing harness added in Phase 4b).

## Phase 6 — Applications, the "so what"  **[FUTURE]**
- Terminal shell over UART, VGA framebuffer text graphics
- Small games (snake) compiled from C running on real hardware
- Stretch: port musl/newlib; stretch-stretch: Linux userspace under a
  minimal custom kernel; full Linux only after Phase 4 is rock-solid

---

## Rules of the road (non-negotiable)
1. **Golden model first, RTL second.** Every uarch change must pass the
   architectural test suite unchanged.
2. Every phase ships with tests + docs.
3. Performance measured in CPI and cycle-accurate sim, never guessed.
4. The ISA never breaks — only grows (new opcodes only in reserved space).
