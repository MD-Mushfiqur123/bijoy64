#!/usr/bin/env python3
"""Minimal stand-in for `iverilog -E` so pyverilog can parse our Verilog
in environments where Icarus Verilog is not installed.

Handles: -E -o <out>, source files, `timescale / `default_nettype removal,
simple object-like `define collection, and `include flattening.
"""
import os
import sys


def preprocess(path, defines, out_lines, stack):
    if path in stack:
        return  # include cycle guard

    with open(path) as f:
        text = f.read()

    stack = stack + [path]
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("`timescale") or line.startswith("`default_nettype"):
            continue
        if line.startswith("`include"):
            inc = line.split("\"")[1] if "\"" in line else line.split()[1].strip("<>")
            inc_path = os.path.join(os.path.dirname(path), inc)
            preprocess(inc_path, defines, out_lines, stack)
            continue
        if line.startswith("`define"):
            toks = line.split()
            if len(toks) >= 2 and "(" not in toks[1]:
                defines.add(toks[1])
            continue
        out_lines.append(raw)


def main():
    args = sys.argv[1:]
    outfile = "pp.out"
    files = []
    i = 0
    while i < len(args):
        if args[i] == "-o":
            outfile = args[i + 1]
            i += 2
        elif args[i] in ("-E",):
            i += 1
        else:
            files.append(args[i])
            i += 1

    lines = []
    for fpath in files:
        preprocess(fpath, set(), lines, [])

    with open(outfile, "w") as f:
        f.write("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
