# Link test: main object (link order defines entry: first object starts at pc 0)
# Calls into t08_lib.asm via .globals (JAL relocation), reads a data table
# exported by the library (LODI + .word data relocations).

    LODI    r1, 33
    JAL     r15, quadruple    # cross-object call -> r2 = 2*(2*33) = 132
    LODI    r8, table_end_ptr # global data symbol in the library
    LD      r9, -8(r8)        # table[-1] = 22
    LD      r11, 0(r8)        # address of `table` (byte 0)
    HLT

# EXPECT r2 = 132
# EXPECT r9 = 22
# EXPECT r11 = 0
