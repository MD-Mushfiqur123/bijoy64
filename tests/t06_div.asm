# MX-Hpi-1 test 6: DIV/REM multi-cycle unit semantics
# (Run with run_tests.py. Exercises the EX busy/freeze path in RTL too.)

    LI      r1, -1234567890123
    LI      r2, 1000000007
    DIV     r3, r1, r2       # truncation toward zero: q = -1234
    REM     r4, r1, r2       # remainder keeps dividend sign: -567881485
    DIV     r5, r1, r0       # divide by zero: q = 0
    REM     r6, r1, r0       # divide by zero: r = dividend
    LODI    r7, 90
    LODI    r8, 7
    DIV     r9, r7, r8       # 12
    REM     r10, r7, r8      # 6
    LODI    r11, 64
    LODI    r12, 64
    DIV     r13, r11, r12    # 1
    REM     r14, r11, r12    # 0
    HLT

# EXPECT r1 = -1234567890123
# EXPECT r2 = 1000000007
# EXPECT r3 = -1234
# EXPECT r4 = -567881485
# EXPECT r5 = 0
# EXPECT r6 = -1234567890123
# EXPECT r7 = 90
# EXPECT r8 = 7
# EXPECT r9 = 12
# EXPECT r10 = 6
# EXPECT r11 = 64
# EXPECT r12 = 64
# EXPECT r13 = 1
# EXPECT r14 = 0
