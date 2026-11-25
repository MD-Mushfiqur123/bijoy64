# BIJOY-64 test 2: loads, stores, memory addressing

    .data
    .word   0xDEADBEEFCAFEBABE
    .word   0x1122334455667788

    .text
    LODI    r1, 8            # address of second data word
    LD      r2, -8(r1)       # r2 = word @0x00
    LD      r3, 0(r1)        # r3 = word @0x08
    LI      r4, 0x0102030405060708
    ST      r4, 16(r0)       # mem[0x10] = r4
    ADDI    r5, r1, 8        # r5 = 0x10
    ST      r2, 0(r5)        # mem[0x10] = 0xDEADBEEFCAFEBABE (overwrite)
    LD      r6, 16(r0)       # r6 = 0xDEADBEEFCAFEBABE
    HLT

# EXPECT r1 = 8
# EXPECT r2 = 0xDEADBEEFCAFEBABE
# EXPECT r3 = 0x1122334455667788
# EXPECT r4 = 0x0102030405060708
# EXPECT r5 = 16
# EXPECT r6 = 0xDEADBEEFCAFEBABE
# EXPECT mem[0x10] = 0xDEADBEEFCAFEBABE
