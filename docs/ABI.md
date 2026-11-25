# MX-Hpi-1 Application Binary Interface

> The contract between hand-written assembly, the assembler/linker, and —
> from Phase 2 on — compilers. The hardware never enforces any of this;
> software agrees on it so code from different sources can call each other.

## 1. Register convention (16 GPRs)

| Register | Name | Role | Preserved across call? |
|---|---|---|---|
| `r0` | `zero` | hardwired 0 (reads as 0, writes ignored) | — |
| `r1` | `rv0` | return value, caller-saved | no |
| `r2` | `rv1` | second return value, caller-saved | no |
| `r3`–`r10` | `a1`–`a8` | integer arguments, caller-saved | no |
| `r11`–`r13` | `t1`–`t3` | caller-saved temporaries | no |
| `r14` | `sp` | stack pointer | **yes** |
| `r15` | `lr` | link register (set by `JAL`, used by `RET`) | **yes** |

Notes:

- With only 16 registers there are no dedicated callee-saved temporaries —
  everything except `sp`/`lr` is caller-saved. A caller with live values
  across a call saves them itself (stack or recompute); a non-leaf function
  must save `lr` before its first `JAL` (leaf functions use `RET` directly).
- Arguments 9+ go on the stack (see §3); return values 3+ on the stack.
- `lr` double-store hazard: a function that both calls others and returns
  must save it. The canonical pattern is in §4.

## 2. Memory map (single data space)

| Range | Use |
|---|---|
| `0x0000–0x3FFF` | instruction memory (16 KB, word-aligned 32-bit insns) |
| `0x0000–0x07FF` | data RAM exposed on FPGA (2 KB usable; sim exposes the full 4 KB `0x000–0xFFF`) |
| `0x0800` | UART TX data (MMIO, FPGA build only) |
| `0x0808` | UART status — bit0 `tx_busy`, bit1 `rx_valid` (MMIO, FPGA only) |
| `0x0810` | UART RX data, read pops (MMIO, FPGA only) |

- Text and data live in separate memories, each addressed from 0 — the ISA
  has no PC-relative data addressing, so data references are absolute.
- Hosted-program convention: `.text` at insn 0, `.data` below the stack,
  initial `sp` = `0x7F8` (top of the 2 KB exposed FPGA RAM; sim-only tools
  may use up to `0xFF8`).
- Everything 8-byte aligned; `sp` must stay 8-byte aligned at call
  boundaries.

## 3. Stack

Grows **down**. A stack frame:

```
        high addr
        |  caller frame ...
        +-----------------+  sp at entry
        |  locals / spills|
sp+0 -> |                 |
        +-----------------+  sp after prologue
        low addr
```

The canonical non-leaf frame pushes the saved `lr` first, so `sp+0` after
the prologue holds it; deeper locals live at positive offsets.

## 4. Canonical prologue/epilogue

Leaf (calls nobody):

```asm
func:
    ADD     r2, r1, r1        # leaf: lr untouched
    RET                       # JALR r0, 0(r15)
```

Non-leaf:

```asm
func:
    ADDI    r14, r14, -8
    ST      r15, 0(r14)       # save lr
    ...
    JAL     r15, other
    ...
    LD      r15, 0(r14)       # restore lr
    ADDI    r14, r14, 8
    RET
```

Caller side:

```asm
    LODI    r1, 33            # seed
    JAL     r15, func         # r1/r2 carry the returns
    # r3..r13 are dead past the call per the convention
```

## 5. Assembler directives

| Directive | Meaning |
|---|---|
| `.global a, b` | export symbols (any section) |
| `.extern a, b` | declare symbols defined elsewhere (informational) |
| `.text` / `.data` | switch section |
| `.word v, sym` | 64-bit data words; `sym` becomes an address relocation |

## 6. Object format & linking (`.mo` v1)

`asmx --emit-obj out.mo in.asm` emits a line-based object:

```
# MX-Hpi-1 object v1
.section text            # 32-bit hex words, relocation slots zero-filled
.section data            # 16-hex-digit words, relocation slots zero-filled
.symbol <name> <GLOBAL|LOCAL> <text|data> <index>
.reloc text <insn index> <type> <symbol>
.reloc data <word index> R_MX_WORD64 <symbol>
```

Relocation types (immediate fields only — opcode/registers are already
encoded in the placeholder word):

| Type | Site | Linker patches |
|---|---|---|
| `R_MX_BR12` | B-type insn | imm12 ← word offset to symbol (`insn[13:2]`) |
| `R_MX_JMP22` | JAL insn | off22 ← word offset to symbol (`insn[21:0]`) |
| `R_MX_LODI18` | LODI insn | imm18 ← absolute **byte** address of symbol (unsigned, insn[17:0]) |
| `R_MX_WORD64` | `.data` word | full 64-bit word ← absolute byte address of symbol |

Link rules (`tools/linker.py`):

1. Text sections concatenate in command-line order; the **first object is
   the entry point** (its text index 0 = pc 0, e.g. `_start`).
2. Data sections concatenate in the same order; a data symbol address =
   data word index × 8, a text symbol address = insn index × 4.
3. Globals must be unique across all objects; locals are namespaced
   `obj<i>.<name>` and only visible inside their object.
4. A relocation symbol resolves object-locally first, then as a global;
   otherwise `undefined symbol` error.
5. Out-of-range immediates (branch beyond ±4 KB, jump beyond ±8 MB, LODI
   address ≥ 256 KB) are link-time errors, not silent truncation.

Example:

```bash
python3 tools/assembler.py tests/link/t08_main.asm --emit-obj main.mo
python3 tools/assembler.py tests/link/t08_lib.asm  --emit-obj lib.mo
python3 tools/linker.py main.mo lib.mo --imem imem.hex --dmem dmem.hex --map map.txt
```

## 7. Guarantees / non-goals

- The pipeline (branch/JAL/JALR semantics, imm ranges) is the *hardware*
  contract and never changes here; this document only layers software
  convention on top.
- No dynamic linking, no PIC, no shared libraries — the data space is flat
  and small by construction.
- Future (Phase 3): the `ecall` convention will be added as a new section
  here, not by breaking this one.
