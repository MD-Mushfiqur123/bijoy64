#!/usr/bin/env python3
"""BIJOY-64 golden model: cycle-accurate-behavior-independent architectural
reference simulator (matched to tools/assembler.py and docs/ISA.md)."""
import sys

MASK64 = (1 << 64) - 1


def sx(value, bits):
    m = 1 << (bits - 1)
    return (value & ((1 << bits) - 1)) - ((value & m) << 1)


def sx64(value, bits):
    return sx(value, bits) & MASK64


def s64(v):
    v &= MASK64
    return v - (1 << 64) if v >= (1 << 63) else v


OP_ADD, OP_SUB, OP_AND, OP_OR, OP_XOR = 0, 1, 2, 3, 4
OP_SLL, OP_SRL, OP_SRA, OP_SLT, OP_SLTU = 5, 6, 7, 8, 9
OP_MUL, OP_DIV, OP_REM = 10, 11, 12


def alu(op, a, b):
    sb = b & 63
    if op == OP_ADD:
        return (a + b) & MASK64
    if op == OP_SUB:
        return (a - b) & MASK64
    if op == OP_AND:
        return a & b
    if op == OP_OR:
        return a | b
    if op == OP_XOR:
        return a ^ b
    if op == OP_SLL:
        return (a << sb) & MASK64
    if op == OP_SRL:
        return (a & MASK64) >> sb
    if op == OP_SRA:
        return (s64(a) >> sb) & MASK64
    if op == OP_SLT:
        return 1 if s64(a) < s64(b) else 0
    if op == OP_SLTU:
        return 1 if (a & MASK64) < (b & MASK64) else 0
    if op == OP_MUL:
        return (s64(a) * s64(b)) & MASK64
    if op == OP_DIV:
        if (b & MASK64) == 0:
            return 0
        q = abs(s64(a)) // abs(s64(b))
        if (s64(a) < 0) != (s64(b) < 0):
            q = -q
        return q & MASK64
    if op == OP_REM:
        if (b & MASK64) == 0:
            return a & MASK64
        r = abs(s64(a)) % abs(s64(b))
        return (-r if s64(a) < 0 else r) & MASK64
    raise ValueError(f"bad alu op {op}")


class Golden:
    def __init__(self, imem_words, dmem_words=()):
        self.imem = list(imem_words)
        self.dmem = {i: w & MASK64 for i, w in enumerate(dmem_words)}
        self.regs = [0] * 16
        self.pc = 0
        self.trace = []

    def rd_word(self, widx):
        return self.dmem.get(widx, 0)

    def wr_word(self, widx, val):
        self.dmem[widx] = val & MASK64

    def step(self):
        op = (self.imem[self.pc >> 2] >> 26) & 0x3F
        ins = self.imem[self.pc >> 2]
        rd = (ins >> 22) & 0xF
        rs1 = (ins >> 18) & 0xF
        rs2 = (ins >> 14) & 0xF
        f3 = (ins >> 11) & 0x7
        imm18 = sx(ins & 0x3FFFF, 18)
        i12 = sx((ins >> 2) & 0xFFF, 12)
        off22 = sx(ins & 0x3FFFFF, 22)
        r1 = self.regs[rs1] if rs1 else 0
        r2 = self.regs[rs2] if rs2 else 0
        npc = (self.pc + 4) & MASK64
        cf_taken = False                    # microarch meta (Phase 1/2c)
        cf_target = npc
        is_cf = False

        if op == 0x00:                      # HLT
            return False
        if op in (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                  0x09, 0x0A, 0x0B, 0x0C, 0x0D):          # R-type
            res = alu(op - 1, r1, r2)
            self.wr(rd, res)
        elif op == 0x10:                    # ADDI
            self.wr(rd, (r1 + sx64(imm18, 18)) & MASK64)
        elif op == 0x11:                    # ANDI
            self.wr(rd, r1 & sx64(imm18, 18))
        elif op == 0x12:                    # ORI  (zero-extended)
            self.wr(rd, r1 | (imm18 & 0x3FFFF))
        elif op == 0x13:                    # XORI
            self.wr(rd, r1 ^ sx64(imm18, 18))
        elif op in (0x14, 0x15, 0x16):      # SLLI/SRLI/SRAI
            sh = ins & 0x3F
            self.wr(rd, alu(op - 0x0F, r1, sh))
        elif op == 0x17:                    # SLTI
            self.wr(rd, alu(OP_SLT, r1, sx64(imm18, 18)))
        elif op == 0x18:                    # SLTIU
            self.wr(rd, alu(OP_SLTU, r1, sx64(imm18, 18)))
        elif op == 0x19:                    # LODI (zero-extended)
            self.wr(rd, ins & 0x3FFFF)
        elif op == 0x1A:                    # LD
            widx = ((r1 + sx64(imm18, 18)) & MASK64) >> 3
            self.wr(rd, self.rd_word(widx))
        elif op == 0x20:                    # ST
            widx = ((r1 + sx64(i12, 12)) & MASK64) >> 3
            self.wr_word(widx, r2)
        elif 0x30 <= op <= 0x35:            # branches
            cond = {
                0x30: r1 == r2,
                0x31: r1 != r2,
                0x32: s64(r1) < s64(r2),
                0x33: s64(r1) >= s64(r2),
                0x34: (r1 & MASK64) < (r2 & MASK64),
                0x35: (r1 & MASK64) >= (r2 & MASK64),
            }[op]
            if cond:
                npc = (self.pc + sx64(i12, 12) * 4) & MASK64
            is_cf = True
            cf_taken = cond
            cf_target = (self.pc + sx64(i12, 12) * 4) & MASK64
        elif op == 0x3D:                    # JALR
            self.wr(rd, npc)
            npc = (r1 + sx64(imm18, 18)) & MASK64
            is_cf = True
            cf_taken = True
            cf_target = npc
        elif op == 0x3E:                    # JAL
            self.wr(rd, npc)
            npc = (self.pc + (sx(off22, 22) << 2)) & MASK64
            is_cf = True
            cf_taken = True
            cf_target = npc
        else:
            raise ValueError(f"illegal opcode {op:#x} at {self.pc:#x}")

        meta = {
            "op": op, "rd": rd,
            "is_cf": is_cf, "cf_taken": cf_taken, "cf_target": cf_target,
        }
        self.trace.append(self.pc)
        self.pc = npc & MASK64
        self.meta = meta
        return meta

    def wr(self, rd, val):
        if rd != 0:
            self.regs[rd] = val & MASK64

    # ------------------------------------------------------------------
    # microarchitectural cycle estimator (Phase 1/2c). Replays the program
    # on a fresh clone (full architectural semantics) and models the RTL:
    #   * 5-stage pipeline, IPC 1  (+4 fill)
    #   * dynamic predictor: 64-entry direct-mapped BTB @ pc[7:2], 2-bit
    #     saturating counters, weakly-taken allocation; mispredict costs +2
    #   * load-use hazard: +1
    #   * DIV/REM multi-cycle freeze: +63
    # It is an estimate: exact RTL cycle counts come from tb_core (iverilog).
    # ------------------------------------------------------------------
    def estimate_cycles(self):
        dmem_words = ([self.dmem[i] for i in range(max(self.dmem) + 1)]
                      if self.dmem else [])
        g = Golden(list(self.imem), dmem_words)
        btb = {}                     # pc -> [counter(0..3), cf_target]
        cycles = 4                   # pipeline fill
        retired = 0

        def uses_rd(ins, rd):
            op = (ins >> 26) & 0x3F
            r1 = (ins >> 18) & 0xF
            r2 = (ins >> 14) & 0xF
            if 0x01 <= op <= 0x0D or op == 0x20:
                return rd == r1 or rd == r2
            if 0x10 <= op <= 0x18 or op == 0x1A or op == 0x3D:
                return rd == r1
            return False

        for _ in range(2_000_000):
            pcs = len(g.trace)
            meta = g.step()
            if not meta:
                return cycles, retired
            retired += 1
            cycles += 1
            pc = g.trace[-1]
            op = meta["op"]

            if meta["is_cf"]:
                taken, target = meta["cf_taken"], meta["cf_target"]
                pred = btb.get(pc)
                pred_taken = pred is not None and bool(pred[0] & 2)
                if pred_taken != taken or (taken and pred[1] != target):
                    cycles += 2                       # mispredict repair
                entry = btb.setdefault(pc, [1, target])
                entry[1] = target
                entry[0] = min(3, entry[0] + 1) if taken else max(0, entry[0] - 1)
            else:
                if op == 0x1A and meta["rd"] != 0:
                    nidx = (pc + 4) >> 2
                    if nidx < len(g.imem) and uses_rd(g.imem[nidx], meta["rd"]):
                        cycles += 1                   # load-use bubble
                if op in (0x0C, 0x0D):
                    cycles += 63                      # DIV/REM freeze
        raise RuntimeError("estimate: max steps exceeded")

    def run(self, max_steps=1_000_000):
        for _ in range(max_steps):
            if not self.step():
                return self.pc
        raise RuntimeError("max steps exceeded (program does not halt?)")


def main():
    import argparse
    from assembler import Assembler

    ap = argparse.ArgumentParser(description="BIJOY-64 golden model")
    ap.add_argument("input")
    ap.add_argument("--regs", action="store_true", help="print r1..r15 at halt")
    ap.add_argument("--mem", action="store_true", help="print nonzero data memory")
    ap.add_argument("--cycles", action="store_true",
                    help="print microarchitectural cycle/CPI estimate (RTL: see tb_core)")
    a = ap.parse_args()

    asm = Assembler()
    words, data = asm.run(open(a.input).read())
    g = Golden(words, data)
    est = g.estimate_cycles() if a.cycles else None
    g.run()
    if a.cycles:
        est_cycles, est_retired = est
        cpi = est_cycles / est_retired if est_retired else 0
        print(f"[cycle estimate: {est_cycles} cycles, {est_retired} retired, "
              f"CPI = {cpi:.3f}]")
    if a.regs:
        for i in range(1, 16):
            print(f"r{i:02d} = 0x{g.regs[i]:016x}")
    if a.mem:
        for widx in sorted(g.dmem):
            v = g.dmem[widx]
            if v:
                print(f"mem[0x{widx*8:04x}] = 0x{v:016x}")
    print(f"[halted at pc=0x{g.pc:04x}, {len(g.trace)} retired instructions]")


if __name__ == "__main__":
    sys.path.insert(0, __file__.rsplit("/", 1)[0])
    main()
