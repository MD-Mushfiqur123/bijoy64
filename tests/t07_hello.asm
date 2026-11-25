# FPGA bring-up: transmit "Hello, MX-Hpi-1\n" over the memory-mapped UART.
# In the golden model the MMIO store lands in RAM at 0x800, so the same file
# doubles as a functional test of the byte-unpack loop.

    LI      r8, 0x800         # UART TX data register
    LODI    r1, 1             # constant 1
    LODI    r2, 8             # bytes per word
    LODI    r9, 0             # word index (string lives in .data, 8 chars/word)
    LODI    r10, 0            # byte counter

next_word:
    SLLI    r11, r9, 3        # byte offset = word * 8
    LD      r12, 0(r11)
    LODI    r13, 0            # byte index in word

next_byte:
    ANDI    r14, r12, 255     # current char = low byte
    BEQ     r14, r0, wdone    # NUL terminator -> string finished
    ST      r14, 0(r8)        # push char to UART TX
    ADD     r10, r10, r1      # chars++
    SRL     r12, r12, r2      # word >>= 8
    ADDI    r13, r13, 1
    BNE     r13, r2, next_byte

wdone:
    ADD     r9, r9, r1        # word++
    LODI    r11, 2
    BNE     r9, r11, next_word
    HLT

    .data
    .word 0x4d202c6f6c6c6548   # "Hello, M"
    .word 0x0a312d6970482d58   # "X-Hpi-1\n"

# EXPECT r9 = 2
# EXPECT r10 = 16
# EXPECT mem[0x800] = 0xA    # last char written is '\n' (golden treats MMIO as RAM)
