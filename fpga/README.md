# FPGA Bring-Up Kit (Phase 1/2d)

Goal: the first physical run of MX-Hpi-1 — **"Hello, MX-Hpi-1" over UART**.

## What's here

| File | Purpose |
|---|---|
| `rtl/mx_hpi_1_fpga_top.v` | FPGA top: core + memories + memory-mapped UART |
| `rtl/fpga_imem.v` / `rtl/fpga_dmem.v` | memory variants whose `$readmemh` init survives synthesis (BRAM init) |
| `rtl/uart_tx.v` / `rtl/uart_rx.v` | 8N1 UART, parameterized `DIVISOR = clk_hz / baud` |
| `rtl/reset_sync.v` | async-assert / sync-release reset |
| `arty_a7/mx_hpi_1_arty.xdc` | Digilent Arty A7-100T constraints (100 MHz, Pmod JA UART) |
| `ice40/mx_hpi_1.pcf` | iCE40-HX8K breakout constraints (12 MHz — verify pins) |
| `../tests/t07_hello.asm` | boot program: streams `Hello, MX-Hpi-1\n` from `.data` to the UART |

## MMIO map

| Address | R/W | Meaning |
|---|---|---|
| `0x000–0x7FF` | RW | 4 KB data RAM |
| `0x800` | W  | UART TX data (low byte; ignored while `busy`) |
| `0x808` | R  | status: bit0 `tx_busy`, bit1 `rx_valid` |
| `0x810` | R  | UART RX data (read pops the byte) |

TX without a busy-wait between stores drops bytes on the floor; see the
echo/monitor program planned for phase 2e (status polling at `0x808`).

## Build & run (Arty A7 / Vivado)

```bash
python3 tools/assembler.py tests/t07_hello.asm --imem imem.hex --dmem dmem.hex
# Vivado: create project (artix7 xc7a100tcsg324-1), add rtl/*.v + fpga/rtl/*.v
#         + arty_a7/mx_hpi_1_arty.xdc, keep imem.hex/dmem.hex in the project cwd,
#         synth → impl → bitstream → program
# Terminal: 115200 8N1 on the Pmod JA USB-UART adapter
```

## Build & run (iCE40-HX8K / open toolchain)

```bash
python3 tools/assembler.py tests/t07_hello.asm --imem imem.hex --dmem dmem.hex
yosys -p "read_verilog rtl/alu64.v rtl/regfile16x64.v rtl/decoder.v rtl/bpu.v \
  rtl/div64.v rtl/mx_hpi_1_core.v rtl/mx_hpi_1_fpga_top.v fpga/rtl/*.v; \
  synth_ice40 -top mx_hpi_1_fpga_top -json mxhpi1.json"
nextpnr-ice40 --hx8k --package ct256 --json mxhpi1.json --pcf fpga/ice40/mx_hpi_1.pcf \
  --asc mxhpi1.asc --freq 12
icepack mxhpi1.asc mxhpi1.bin && iceprog mxhpi1.bin
```

Note on clocking: bring-up runs the core directly on the board oscillator —
no PLL. UART timing comes entirely from `BAUD_DIV` (868 @ 100 MHz / 115200,
417 @ 12 MHz — override the parameter for iCE40). Vendor PLL/MMCM wrappers
are deliberately deferred until timing analysis demands them.

## Pre-silicon check (iverilog machine)

```bash
iverilog -o sim/tb_uart fpga/rtl/uart_tx.v fpga/rtl/uart_rx.v tb/tb_uart.v
vvp sim/tb_uart            # expect: TB_UART PASS received=a5
```
