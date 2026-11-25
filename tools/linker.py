#!/usr/bin/env python3
"""MX-Hpi-1 linker: .mo objects -> imem.hex / dmem.hex + link map

Consumes the object format produced by `asmx --emit-obj` (docs/ABI.md):
layout is text sections concatenated in argument order, then data sections
appended in order. Globals must be unique; relocation symbols resolve
object-locally first, then globally.
"""
import argparse
import sys


def parse_mobj(path):
    obj = {"text": [], "data": [], "symbols": {}, "relocs": [], "data_relocs": []}
    sect = None
    for lineno, raw in enumerate(open(path).read().splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line or line.startswith("#"):
            continue
        toks = line.split()
        if toks[0] == ".section":
            sect = toks[1]
        elif toks[0] == ".symbol":
            obj["symbols"][toks[1]] = (toks[2], toks[3], int(toks[4]))
        elif toks[0] == ".reloc":
            if toks[1] == "text":
                obj["relocs"].append((int(toks[2]), toks[3], toks[4]))
            else:
                obj["data_relocs"].append((int(toks[2]), toks[4]))
        elif sect == "text":
            obj["text"].append(int(toks[0], 16))
        elif sect == "data":
            obj["data"].append(int(toks[0], 16))
        else:
            sys.exit(f"{path}:{lineno}: bad line: {line}")
    return obj


def link_objects(objs, map_path=None):
    """objs: list of assembler.to_object() dicts, in link order.

    Returns (words, data, map_lines). Raises LinkError on issues.
    """
    words, data = [], []
    for o in objs:
        words += o["text"]
    for o in objs:
        data += o["data"]

    resolved = {}
    for i, o in enumerate(objs):
        tbase = sum(len(x["text"]) for x in objs[:i])
        dbase = sum(len(x["data"]) for x in objs[:i])
        for name, (bind, sect, idx) in o["symbols"].items():
            key = name if bind == "GLOBAL" else f"obj{i}.{name}"
            if key in resolved:
                raise LinkError(f"duplicate global symbol '{name}'")
            resolved[key] = ((tbase + idx) * 4 if sect == "text"
                             else (dbase + idx) * 8)

    def sym_addr(oi, name):
        if name in objs[oi]["symbols"]:
            bind, sect, idx = objs[oi]["symbols"][name]
            key = name if bind == "GLOBAL" else f"obj{oi}.{name}"
            return resolved[key]
        if name in resolved:
            return resolved[name]
        raise LinkError(f"undefined symbol '{name}'")

    for oi, o in enumerate(objs):
        tbase = sum(len(x["text"]) for x in objs[:oi])
        dbase = sum(len(x["data"]) for x in objs[:oi])

        for idx, typ, sym in o["relocs"]:
            i = tbase + idx
            addr = sym_addr(oi, sym)
            w = words[i]
            if typ == "R_MX_BR12":
                off = addr // 4 - i
                if not -(1 << 11) <= off < (1 << 11):
                    raise LinkError(f"branch to '{sym}' out of imm12 range "
                                    f"({off} words from insn {i})")
                words[i] = w | ((off & 0xFFF) << 2)
            elif typ == "R_MX_JMP22":
                off = addr // 4 - i
                if not -(1 << 21) <= off < (1 << 21):
                    raise LinkError(f"jump to '{sym}' out of off22 range")
                words[i] = w | (off & 0x3FFFFF)
            elif typ == "R_MX_LODI18":
                if not 0 <= addr < (1 << 18):
                    raise LinkError(f"symbol '{sym}' ({addr:#x}) does not fit "
                                    f"an 18-bit LODI immediate")
                words[i] = w | (addr & 0x3FFFF)
            else:
                raise LinkError(f"unknown relocation type '{typ}'")

        for idx, sym in o["data_relocs"]:
            data[dbase + idx] = sym_addr(oi, sym)

    n = len(objs)
    lines = [f"MX-Hpi-1 link map ({n} object{'s' if n > 1 else ''}, "
             f"{len(words)} insns, {len(data)} data words)"]
    for i, o in enumerate(objs):
        lines.append(f"  obj{i}: text@0x{sum(len(x['text']) for x in objs[:i]) * 4:x} "
                     f"data@0x{sum(len(x['data']) for x in objs[:i]) * 8:x} "
                     f"globals={sorted(k for k, (b, _, __) in o['symbols'].items() if b == 'GLOBAL')}")
    if map_path:
        with open(map_path, "w") as f:
            f.write("\n".join(lines) + "\n")
            for name in sorted(resolved):
                f.write(f"{resolved[name]:#06x}  {name}\n")
    return words, data, lines


class LinkError(Exception):
    pass


def main():
    ap = argparse.ArgumentParser(description="MX-Hpi-1 linker")
    ap.add_argument("objects", nargs="+", help=".mo object files, link order")
    ap.add_argument("--imem", default="imem.hex")
    ap.add_argument("--dmem", default="dmem.hex")
    ap.add_argument("--map", dest="map_path", default=None,
                    help="write a symbol/cycle map file")
    a = ap.parse_args()

    objs = [parse_mobj(p) for p in a.objects]
    try:
        words, data, lines = link_objects(objs, a.map_path)
    except LinkError as e:
        sys.exit(f"link failed: {e}")

    with open(a.imem, "w") as f:
        f.write("".join(f"{w:08x}\n" for w in words))
    with open(a.dmem, "w") as f:
        f.write("".join(f"{w:016x}\n" for w in data))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
