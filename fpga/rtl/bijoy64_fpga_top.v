// ---------------------------------------------------------------------------
// bijoy64_fpga_top.v -- BIJOY-64 FPGA bring-up top level
//
// Core + FPGA memory variants + memory-mapped I/O. Single clock domain (the
// board oscillator); no PLL needed for first bring-up, UART baud comes from
// the BAUD_DIV parameter.
//
// MMIO map (data-space addresses):
//   0x000-0x7FF  4 KB data RAM (fpga_dmem)
//   0x800        UART TX data      (store: byte = wdata[7:0], ignored if busy)
//   0x808        UART status       (load: bit0 = tx_busy, bit1 = rx_valid)
//   0x810        UART RX data      (load: pops the received byte)
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module bijoy64_fpga_top #(
    parameter BAUD_DIV = 868          // 100 MHz / 115200
) (
    input  wire       clk,
    input  wire       arst_n_in,
    input  wire       uart_rx_pin,
    output wire       uart_tx_pin,
    output wire [3:0] led
);
    wire rst_n;
    reset_sync u_reset (
        .clk       (clk),
        .arst_n_in (arst_n_in),
        .rst_n     (rst_n)
    );

    wire [63:0] imem_addr;
    wire [31:0] imem_rdata;
    wire [63:0] dmem_addr;
    wire        dmem_re, dmem_we;
    wire [63:0] dmem_wdata;
    wire        halted;

    bijoy64_core u_core (
        .clk        (clk),
        .rst_n      (rst_n),
        .imem_addr  (imem_addr),
        .imem_rdata (imem_rdata),
        .dmem_addr  (dmem_addr),
        .dmem_re    (dmem_re),
        .dmem_we    (dmem_we),
        .dmem_wdata (dmem_wdata),
        .dmem_rdata (dmem_rdata),
        .halted     (halted)
    );

    fpga_imem u_imem (
        .addr  (imem_addr),
        .rdata (imem_rdata)
    );

    wire        io_sel = dmem_addr[11];
    wire        ram_re = dmem_re && !io_sel;
    wire        ram_we = dmem_we && !io_sel;
    wire [63:0] ram_rdata;

    fpga_dmem u_dmem (
        .clk   (clk),
        .addr  (dmem_addr),
        .re    (ram_re),
        .rdata (ram_rdata),
        .we    (ram_we),
        .wdata (dmem_wdata)
    );

    wire       tx_busy;
    wire       rx_valid;
    wire [7:0] rx_data;
    wire       rx_ack = dmem_re && io_sel && (dmem_addr[5:3] == 3'b010);

    uart_tx #(
        .DIVISOR (BAUD_DIV)
    ) u_tx (
        .clk   (clk),
        .rst_n (rst_n),
        .data  (dmem_wdata[7:0]),
        .we    (dmem_we && io_sel && (dmem_addr[5:3] == 3'b000)),
        .busy  (tx_busy),
        .txd   (uart_tx_pin)
    );

    uart_rx #(
        .DIVISOR (BAUD_DIV)
    ) u_rx (
        .clk   (clk),
        .rst_n (rst_n),
        .rx    (uart_rx_pin),
        .ack   (rx_ack),
        .data  (rx_data),
        .valid (rx_valid)
    );

    reg [63:0] io_rdata;
    always @(*) begin
        case (dmem_addr[5:3])
            3'b000:  io_rdata = 64'd0;                      // TX data: write-only
            3'b001:  io_rdata = {62'd0, rx_valid, tx_busy}; // status
            3'b010:  io_rdata = {56'd0, rx_data};           // RX data (pop)
            default: io_rdata = 64'd0;
        endcase
    end

    assign dmem_rdata = io_sel ? io_rdata : ram_rdata;
    assign led = {3'b000, halted};
endmodule
