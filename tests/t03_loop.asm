# BIJOY-64 test 3: loop with branches -- sum 1..10 = 55, plus factorial 5 = 120

    LODI    r1, 10           # i
    LODI    r2, 0            # sum
    LODI    r3, 0            # counter
loop:
    ADDI    r3, r3, 1
    ADD     r2, r2, r3
    BNE     r3, r1, loop     # until counter == 10

    # factorial(5)
    LODI    r4, 5            # n
    LODI    r5, 1            # acc
fact:
    MUL     r5, r5, r4
    ADDI    r4, r4, -1
    BNE     r4, r0, fact

    HLT

# EXPECT r1 = 10
# EXPECT r2 = 55
# EXPECT r3 = 10
# EXPECT r4 = 0
# EXPECT r5 = 120
