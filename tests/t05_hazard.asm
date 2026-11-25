# MX-Hpi-1 test 5: pipeline hazards -- forwarding, load-use, back-to-back deps

    LODI    r1, 100
    ADD     r2, r1, r1       # r2 = 200   (EX->EX forward)
    SUB     r3, r2, r1       # r3 = 100   (MEM->EX forward)
    ST      r3, 0(r0)        # store 100  (MEM->EX forward on rs2)
    LD      r4, 0(r0)        # r4 = 100
    ADD     r5, r4, r4       # r5 = 200   (load-use: 1 bubble + EX->EX fwd)
    ST      r5, 8(r0)        # store 200  (load-use on rs2)
    LD      r6, 8(r0)        # r6 = 200
    BEQ     r4, r3, ok       # taken: 100 == 100
    LODI    r7, 999          # skipped (flushed)
    HLT
ok:
    ADDI    r7, r6, 1        # r7 = 201
    JAL     r0, done
    LODI    r8, 888          # skipped
done:
    HLT

# EXPECT r1 = 100
# EXPECT r2 = 200
# EXPECT r3 = 100
# EXPECT r4 = 100
# EXPECT r5 = 200
# EXPECT r6 = 200
# EXPECT r7 = 201
# EXPECT r8 = 0
# EXPECT mem[0x00] = 100
# EXPECT mem[0x08] = 200
