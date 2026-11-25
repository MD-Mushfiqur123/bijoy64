# BIJOY-64 test 1: arithmetic / logic / compare / mul / div
#
#  r1 = 20, r2 = 6
#  r3 = r1 + r2        = 26
#  r4 = r1 - r2        = 14
#  r5 = r1 & r2        = 4
#  r6 = r1 | r2        = 22
#  r7 = r1 ^ r2        = 18
#  r8 = r1 << 3        = 160
#  r9 = -128 >>a 3     = -16
#  r10 = (-1 < 1)      = 1
#  r11 = (5 <u 3)      = 0
#  r12 = 7 * 6         = 42
#  r13 = 100 / 9       = 11
#  r14 = 100 % 9       = 1
#  r15 = 0xFFFF0000_00000001 via LI

    LODI    r1, 20
    LODI    r2, 6
    ADD     r3, r1, r2
    SUB     r4, r1, r2
    AND     r5, r1, r2
    OR      r6, r1, r2
    XOR     r7, r1, r2
    LODI    r8, 3
    SLL     r8, r1, r8
    LI      r10, -128
    LODI    r9, 3
    SRA     r9, r10, r9
    LI      r11, -1
    LODI    r12, 1
    SLT     r13, r11, r12
    LODI    r14, 5
    LODI    r15, 3
    SLTU    r13, r14, r15
    LODI    r14, 7
    MUL     r12, r14, r2
    LODI    r14, 100
    LODI    r15, 9
    DIV     r13, r14, r15
    REM     r14, r14, r15
    LI      r15, 0xFFFF000000000001
    HLT

# EXPECT r1 = 20
# EXPECT r2 = 6
# EXPECT r3 = 26
# EXPECT r4 = 14
# EXPECT r5 = 4
# EXPECT r6 = 22
# EXPECT r7 = 18
# EXPECT r8 = 160
# EXPECT r9 = -16
# EXPECT r10 = -128
# EXPECT r11 = -1
# EXPECT r12 = 42
# EXPECT r13 = 11
# EXPECT r14 = 1
# EXPECT r15 = 0xFFFF000000000001
