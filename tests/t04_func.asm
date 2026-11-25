# MX-Hpi-1 test 4: function calls (JAL / JALR), link register

    # r1 = 33, r2 = -9 ; call double_add: r3 = 2*r1 + r2 = 57
    LODI    r1, 33
    LI      r2, -9
    JAL     r15, double_add
    HLT

double_add:
    ADD     r4, r1, r1       # 2*r1
    ADD     r3, r4, r2
    RET                      # JALR r0, 0(r15)

# EXPECT r1 = 33
# EXPECT r2 = -9
# EXPECT r3 = 57
# EXPECT r4 = 66
# EXPECT r15 = 36            # return address = instruction after JAL
