// ---------------------------------------------------------------------------
// tb_uart.v -- TX->RX loopback check for the FPGA UART pair
// Run with iverilog on a machine that has it (see fpga/README.md).
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_uart;
    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg [7:0] txdata;
    reg txwe;
    reg rxack;

    wire txd;
    wire busy;
    wire [7:0] rxdata;
    wire rxvalid;

    always #5 clk = ~clk;             // 100 MHz

    uart_tx #(.DIVISOR(8)) u_tx (
        .clk(clk), .rst_n(rst_n),
        .data(txdata), .we(txwe),
        .busy(busy), .txd(txd)
    );

    uart_rx #(.DIVISOR(8)) u_rx (
        .clk(clk), .rst_n(rst_n),
        .rx(txd), .ack(rxack),
        .data(rxdata), .valid(rxvalid)
    );

    initial begin
        txdata = 8'h00; txwe = 1'b0; rxack = 1'b0;
        #25 rst_n = 1'b1;
        @(negedge busy);
        @(posedge clk); txdata = 8'hA5; txwe = 1'b1;
        @(posedge clk); txwe = 1'b0;
        wait (rxvalid === 1'b1);
        @(posedge clk);
        if (rxdata === 8'hA5)
            $display("TB_UART PASS received=%02x", rxdata);
        else
            $display("TB_UART FAIL received=%02x expected=a5", rxdata);
        $finish;
    end
endmodule
