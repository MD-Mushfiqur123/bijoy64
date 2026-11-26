# Link test library object. `double` is a leaf (uses LR directly, no save);
# `quadruple` is a non-leaf and shows the canonical ABI prologue/epilogue.

    .global quadruple, table_end_ptr

double:
    ADD     r2, r1, r1        # r2 = 2 * r1
    RET

quadruple:
    ADDI    r14, r14, -8      # push frame
    ST      r15, 0(r14)       # save caller's LR
    JAL     r15, double
    SLLI    r2, r2, 1         # r2 = 4 * r1
    LD      r15, 0(r14)       # restore LR
    ADDI    r14, r14, 8       # pop frame
    RET

    .data
table:
    .word 11, 22
table_end_ptr:                # global: end address of the table
    .word table               # local symbol -> R_MX_WORD64 data relocation
