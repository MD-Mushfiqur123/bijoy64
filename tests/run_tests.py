#!/usr/bin/env python3
"""MX-Hpi-1 test runner.

For every tests/*.asm:
  1. assemble into build/<name>/imem.hex + dmem.hex
  2. run the Python golden model and diff against '# EXPECT' lines
  3. pyverilog-parse all RTL + tb files (syntax gate; full sim needs iverilog)
"""
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "tools"))
sys.path.insert(0, HERE)

from assembler import Assembler, AsmError
from golden import Golden, MASK64
from linker import link_objects, LinkError

RTL = ["rtl/alu64.v", "rtl/regfile16x64.v", "rtl/decoder.v", "rtl/bpu.v",
       "rtl/div64.v", "rtl/mx_hpi_1_core.v", "rtl/imem.v", "rtl/dmem.v",
       "rtl/mx_hpi_1_top.v",
       "fpga/rtl/reset_sync.v", "fpga/rtl/uart_tx.v", "fpga/rtl/uart_rx.v",
       "fpga/rtl/fpga_imem.v", "fpga/rtl/fpga_dmem.v",
       "fpga/rtl/mx_hpi_1_fpga_top.v"]
TB = ["tb/tb_core.v", "tb/tb_uart.v"]

# (main .asm, [library .asm...]) — objects linked with assembler+linker;
# the first object is the entry point (pc 0), EXPECT lines come from main
LINK_TESTS = [(["link/t08_main.asm", "link/t08_lib.asm"], "link/t08_main.asm")]

EXPECT_REG = re.compile(r"#\s*EXPECT\s+r([0-9]|1[0-5])\s*=\s*(\S+)")
EXPECT_MEM = re.compile(r"#\s*EXPECT\s+mem\[0x([0-9a-fA-F]+)\]\s*=\s*(\S+)")


def run_golden(asm_path):
    asm = Assembler()
    words, data = asm.run(open(asm_path).read())
    g = Golden(words, data)
    g.run()

    failures = []
    checked = 0
    for line in open(asm_path):
        m = EXPECT_REG.search(line)
        if m:
            idx, val = int(m.group(1)), m.group(2)
            want = int(val, 0) & MASK64
            got = g.regs[idx]
            checked += 1
            if got != want:
                failures.append(f"r{idx}: expected 0x{want:016x}, got 0x{got:016x} ({val})")
            continue
        m = EXPECT_MEM.search(line)
        if m:
            addr, val = int(m.group(1), 16), m.group(2)
            want = int(val, 0) & MASK64
            got = g.rd_word(addr >> 3)
            checked += 1
            if got != want:
                failures.append(f"mem[0x{addr:x}]: expected 0x{want:016x}, got 0x{got:016x} ({val})")
    return words, data, g, failures, checked


def lint_verilog():
    from pyverilog.vparser.parser import parse
    files = [os.path.join(ROOT, f) for f in RTL + TB]
    shim = os.path.join(ROOT, "tools", "pp_shim.py")
    tmpdir = tempfile.mkdtemp()

    wrapper = os.path.join(tmpdir, "ivshim")
    with open(wrapper, "w") as f:
        f.write("#!/bin/sh\nexec python3 %s \"$@\"\n" % shim)
    os.chmod(wrapper, 0o755)

    os.environ["PYVERILOG_IVERILOG"] = wrapper

    cwd = os.getcwd()
    os.chdir(tmpdir)
    try:
        ast, _ = parse(files)
        mods = [d for d in ast.description.definitions
                if d.__class__.__name__ in ("Module", "ModuleDef")]
        return [d.name for d in mods]
    finally:
        os.chdir(cwd)


def run_link_group(files, main_name):
    """Assemble each file to an object, link, run golden, diff main's EXPECTs."""
    objs = []
    for rel in files:
        asm = Assembler()
        objs.append(asm.to_object(open(os.path.join(ROOT, "tests", rel)).read()))
    words, data, _ = link_objects(objs)

    g = Golden(words, data)
    g.run()

    failures = []
    checked = 0
    main_path = os.path.join(ROOT, "tests", main_name)
    for line in open(main_path):
        m = EXPECT_REG.search(line)
        if m:
            idx, val = int(m.group(1)), m.group(2)
            want = int(val, 0) & MASK64
            got = g.regs[idx]
            checked += 1
            if got != want:
                failures.append(f"r{idx}: expected 0x{want:016x}, got 0x{got:016x} ({val})")
            continue
        m = EXPECT_MEM.search(line)
        if m:
            addr, val = int(m.group(1), 16), m.group(2)
            want = int(val, 0) & MASK64
            got = g.rd_word(addr >> 3)
            checked += 1
            if got != want:
                failures.append(f"mem[0x{addr:x}]: expected 0x{want:016x}, got 0x{got:016x} ({val})")
    return g, failures, checked


def main():
    print("== pyverilog syntax lint ==")
    try:
        mods = lint_verilog()
        print("Parsed OK: %d modules: %s" % (len(mods), ", ".join(mods)))
    except Exception as e:
        print("VERILOG LINT FAILED: %r" % e)
        return 1

    print("\n== golden-model checks ==")
    build = os.path.join(ROOT, "build")
    os.makedirs(build, exist_ok=True)

    total_pass = 0
    total_fail = 0
    for name in sorted(os.listdir(os.path.join(ROOT, "tests"))):
        if not name.endswith(".asm"):
            continue
        path = os.path.join(ROOT, "tests", name)
        bdir = os.path.join(build, name[:-4])
        os.makedirs(bdir, exist_ok=True)
        try:
            words, data, g, failures, checked = run_golden(path)
        except (AsmError, RuntimeError, ValueError) as e:
            print("%s: FAILED (%s)" % (name, e))
            total_fail += 1
            continue

        with open(os.path.join(bdir, "imem.hex"), "w") as f:
            f.write("".join("%08x\n" % w for w in words))
        with open(os.path.join(bdir, "dmem.hex"), "w") as f:
            f.write("".join("%016x\n" % w for w in data))

        if failures:
            print("%s: FAILED (%d mismatch over %d checks)" % (name, len(failures), checked))
            for f in failures:
                print("    " + f)
            total_fail += 1
        else:
            print("%s: PASS (%d checks, %d insns retired)" % (name, checked, len(g.trace)))
            total_pass += 1

    print("\n== linker checks (assembler objects + cross-file symbols) ==")
    for files, main_name in LINK_TESTS:
        label = " + ".join(files)
        try:
            g, failures, checked = run_link_group(files, main_name)
        except (AsmError, RuntimeError, ValueError, LinkError) as e:
            print("%s: FAILED (%s)" % (label, e))
            total_fail += 1
            continue
        if failures:
            print("%s: FAILED (%d mismatch over %d checks)" % (label, len(failures), checked))
            for f in failures:
                print("    " + f)
            total_fail += 1
        else:
            print("%s: PASS (%d checks, %d insns retired)" % (label, checked, len(g.trace)))
            total_pass += 1

    print("\nSummary: %d passed, %d failed" % (total_pass, total_fail))
    return 1 if total_fail else 0


if __name__ == "__main__":
    sys.exit(main())
