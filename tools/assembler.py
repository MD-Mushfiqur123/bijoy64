#!/usr/bin/env python3
"""MX-Hpi-1 assembler: .asm -> imem.hex / dmem.hex

See docs/ISA.md for the instruction set definition.
"""
import argparse
import re
import sys

OPCODES = {
    "HLT": 0x00,
    "ADD": 0x01, "SUB": 0x02, "AND": 0x03, "OR": 0x04, "XOR": 0x05,
    "SLL": 0x06, "SRL": 0x07, "SRA": 0x08, "SLT": 0x09, "SLTU": 0x0A,
    "MUL": 0x0B, "DIV": 0x0C, "REM": 0x0D,
    "ADDI": 0x10, "ANDI": 0x11, "ORI": 0x12, "XORI": 0x13,
    "SLLI": 0x14, "SRLI": 0x15, "SRAI": 0x16, "SLTI": 0x17, "SLTIU": 0x18,
    "LODI": 0x19, "LD": 0x1A,
    "ST": 0x20,
    "BEQ": 0x30, "BNE": 0x31, "BLT": 0x32, "BGE": 0x33, "BLTU": 0x34, "BGEU": 0x35,
    "JALR": 0x3D, "JAL": 0x3E,
}
R_TYPE = {"ADD", "SUB", "AND", "OR", "XOR", "SLL", "SRL", "SRA", "SLT", "SLTU", "MUL", "DIV", "REM"}
I_TYPE = {"ADDI", "ANDI", "ORI", "XORI", "SLLI", "SRLI", "SRAI", "SLTI", "SLTIU", "LODI", "LD", "JALR"}
B_TYPE = {"BEQ", "BNE", "BLT", "BGE", "BLTU", "BGEU"}

MASK64 = (1 << 64) - 1


class AsmError(Exception):
    pass


def parse_reg(tok, lineno):
    m = re.fullmatch(r"[rx]([0-9]|1[0-5])", tok)
    if not m:
        raise AsmError(f"line {lineno}: bad register '{tok}'")
    return int(m.group(1))


def parse_int(tok, lineno):
    try:
        v = int(tok, 0)
    except ValueError:
        raise AsmError(f"line {lineno}: bad integer '{tok}'")
    if v < 0:
        v &= MASK64
    return v


def sx(value, bits):
    m = 1 << (bits - 1)
    return (value & ((1 << bits) - 1)) - ((value & m) << 1)


class Assembler:
    def __init__(self):
        self.flow = []         # (lineno, mnemonic, args), pseudo-expansion applied
        self.data_words = []   # 64-bit words, word index 0 = address 0
        self.labels = {}       # label -> index into flow
        self.section = ".text"

    def assemble(self, text):
        for lineno, raw in enumerate(text.splitlines(), 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            if line.startswith("."):
                self.directive(line, lineno)
                continue
            label = None
            if ":" in line:
                label, line = line.split(":", 1)
                label = label.strip()
                line = line.strip()
            if self.section == ".text":
                if label is not None:
                    self.labels[label] = len(self.flow)
                if line:
                    for ln, mn, args in self.expand(lineno, line):
                        self.flow.append((ln, mn, args))
            else:
                if label is not None:
                    raise AsmError(f"line {lineno}: data labels not supported yet")
                for tok in line.split(","):
                    self.data_words.append(parse_int(tok.strip(), lineno))

    def directive(self, line, lineno):
        d = line.split()
        if d[0] == ".text":
            self.section = ".text"
        elif d[0] == ".data":
            self.section = ".data"
        elif d[0] == ".word":
            if self.section != ".data":
                raise AsmError(f"line {lineno}: .word outside .data")
            for tok in d[1:]:
                self.data_words.append(parse_int(tok, lineno))
        else:
            raise AsmError(f"line {lineno}: unknown directive '{d[0]}'")

    # ------------------------------------------------------------------
    def enc_r(self, op, rd, rs1, rs2):
        return (rs2 << 14) | (rs1 << 18) | (rd << 22) | (op << 26)

    def enc_i(self, op, rd, rs1, imm18):
        return (imm18 & 0x3FFFF) | (rs1 << 18) | (rd << 22) | (op << 26)

    def enc_s(self, op, rs1, rs2, imm12):
        if not -(1 << 11) <= imm12 < (1 << 11):
            raise AsmError(f"imm12 out of range: {imm12}")
        return ((imm12 & 0xFFF) << 2) | (rs2 << 14) | (rs1 << 18) | (op << 26)

    def enc_j(self, op, rd, off22):
        if not -(1 << 21) <= off22 < (1 << 21):
            raise AsmError(f"off22 out of range: {off22}")
        return ((off22 & 0x3FFFFF) << 0) | (rd << 22) | (op << 26)

    # ------------------------------------------------------------------
    def expand(self, lineno, line):
        """Return list of (lineno, mnemonic, [args]) tuples."""
        toks = line.replace(",", " ").split()
        mn = toks[0].upper()
        args = toks[1:]
        if mn == "NOP":
            return [(lineno, "ADDI", ["r0", "r0", "0"])]
        if mn in ("LI", "LODI64"):
            if len(args) != 2:
                raise AsmError(f"line {lineno}: {mn} needs 2 args")
            rd = parse_reg(args[0], lineno)
            imm = parse_int(args[1], lineno)
            if imm >= (1 << 63):
                imm -= 1 << 64
            chunks = [(imm >> (18 * i)) & 0x3FFFF for i in range(4)]
            out = [(lineno, "LODI", [f"r{rd}", str(chunks[3])])]
            for c in chunks[2::-1]:
                out += [(lineno, "SLLI", [f"r{rd}", f"r{rd}", "18"]),
                        (lineno, "ORI", [f"r{rd}", f"r{rd}", str(c)])]
            return out
        if mn == "J":
            return [(lineno, "JAL", ["r0", args[0]])]
        if mn == "RET":
            return [(lineno, "JALR", ["r0", "0(r15)"])]
        return [(lineno, mn, args)]

    def emit(self, lineno, mn, args):
        if mn == "HLT":
            return [self.enc_r(0x00, 0, 0, 0)]
        if mn in R_TYPE:
            if len(args) != 3:
                raise AsmError(f"line {lineno}: {mn} needs 3 register args")
            rd, rs1, rs2 = [parse_reg(a, lineno) for a in args]
            return [self.enc_r(OPCODES[mn], rd, rs1, rs2)]

        if mn == "ST":
            rs2 = parse_reg(args[0], lineno)
            m = re.fullmatch(r"([+-]?\w+)\((\w+)\)", args[1])
            if not m:
                raise AsmError(f"line {lineno}: bad ST address operand '{args[1]}'")
            off = parse_int(m.group(1), lineno)
            if off >= (1 << 63):
                off -= 1 << 64
            rs1 = parse_reg(m.group(2), lineno)
            return [self.enc_s(OPCODES["ST"], rs1, rs2, off)]

        if mn == "LD":
            rd = parse_reg(args[0], lineno)
            m = re.fullmatch(r"([+-]?\w+)\((\w+)\)", args[1])
            if not m:
                raise AsmError(f"line {lineno}: bad LD address operand '{args[1]}'")
            off = parse_int(m.group(1), lineno)
            if off >= (1 << 63):
                off -= 1 << 64
            rs1 = parse_reg(m.group(2), lineno)
            return [self.enc_i(OPCODES["LD"], rd, rs1, off)]

        if mn == "LODI":
            rd = parse_reg(args[0], lineno)
            imm = parse_int(args[1], lineno)
            if not 0 <= imm < (1 << 18):
                raise AsmError(f"line {lineno}: LODI takes an 18-bit unsigned imm; "
                               f"use LI for wider/negative values")
            return [self.enc_i(OPCODES["LODI"], rd, 0, imm)]

        if mn in ("ADDI", "ANDI", "XORI", "SLTI", "SLTIU"):
            rd = parse_reg(args[0], lineno)
            rs1 = parse_reg(args[1], lineno)
            imm = parse_int(args[2], lineno)
            if imm >= (1 << 63):
                imm -= 1 << 64
            if not -(1 << 17) <= imm < (1 << 17):
                raise AsmError(f"line {lineno}: imm18 too big for {mn}: {imm}")
            return [self.enc_i(OPCODES[mn], rd, rs1, imm)]

        if mn == "ORI":
            rd = parse_reg(args[0], lineno)
            rs1 = parse_reg(args[1], lineno)
            imm = parse_int(args[2], lineno)
            if not 0 <= imm < (1 << 18):
                raise AsmError(f"line {lineno}: ORI takes an 18-bit unsigned imm (zero-extended): {imm}")
            return [self.enc_i(OPCODES["ORI"], rd, rs1, imm)]

        if mn in ("SLLI", "SRLI", "SRAI"):
            rd = parse_reg(args[0], lineno)
            rs1 = parse_reg(args[1], lineno)
            imm = parse_int(args[2], lineno)
            if not 0 <= imm < 64:
                raise AsmError(f"line {lineno}: shift amount out of range: {imm}")
            return [self.enc_i(OPCODES[mn], rd, rs1, imm)]

        if mn == "JALR":
            rd = parse_reg(args[0], lineno)
            m = re.fullmatch(r"([+-]?\w+)\((\w+)\)", args[1])
            if not m:
                raise AsmError(f"line {lineno}: bad JALR operand '{args[1]}'")
            off = parse_int(m.group(1), lineno)
            if off >= (1 << 63):
                off -= 1 << 64
            rs1 = parse_reg(m.group(2), lineno)
            return [self.enc_i(OPCODES["JALR"], rd, rs1, off)]

        if mn in B_TYPE:
            rs1 = parse_reg(args[0], lineno)
            rs2 = parse_reg(args[1], lineno)
            target = args[2]
            return [("B", lineno, OPCODES[mn], rs1, rs2, target)]
        if mn == "JAL":
            rd = parse_reg(args[0], lineno)
            target = args[1]
            return [("J", lineno, rd, target)]
        raise AsmError(f"line {lineno}: unknown instruction '{mn}'")

    def resolve(self, emitted):
        """Second pass: patch label references (pc-relative offsets)."""
        words = []
        for i, item in enumerate(emitted):
            if isinstance(item, int):
                words.append(item & 0xFFFFFFFF)
                continue
            if item[0] == "B":
                _, lineno, op, rs1, rs2, target = item
                if target not in self.labels:
                    raise AsmError(f"line {lineno}: unknown label '{target}'")
                off = (self.labels[target] - i) * 4
                words.append(self.enc_s(op, rs1, rs2, off >> 2) & 0xFFFFFFFF)
            else:
                _, lineno, rd, target = item
                if target not in self.labels:
                    raise AsmError(f"line {lineno}: unknown label '{target}'")
                off = (self.labels[target] - i) * 4
                words.append(self.enc_j(OPCODES["JAL"], rd, off >> 2) & 0xFFFFFFFF)
        return words

    def run(self, text):
        self.assemble(text)
        emitted = []
        for ln, mn, args in self.flow:
            emitted += self.emit(ln, mn, args)
        return self.resolve(emitted), self.data_words


def main():
    ap = argparse.ArgumentParser(description="MX-Hpi-1 assembler")
    ap.add_argument("input")
    ap.add_argument("--imem", default="imem.hex")
    ap.add_argument("--dmem", default="dmem.hex")
    ap.add_argument("--dump", action="store_true", help="print instruction words")
    a = ap.parse_args()

    asm = Assembler()
    try:
        words, data = asm.run(open(a.input).read())
    except AsmError as e:
        sys.exit(f"assembly failed: {e}")

    with open(a.imem, "w") as f:
        f.write("".join(f"{w:08x}\n" for w in words))
    with open(a.dmem, "w") as f:
        f.write("".join(f"{w:016x}\n" for w in data))

    if a.dump:
        for i, w in enumerate(words):
            print(f"{i*4:08x}: {w:08x}")
        print(f"[{len(words)} instructions, {len(data)} data words]")


if __name__ == "__main__":
    main()
