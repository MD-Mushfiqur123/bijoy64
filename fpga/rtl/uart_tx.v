// ---------------------------------------------------------------------------
// uart_tx.v -- 8N1 UART transmitter (no FIFO; single-buffered)
// Push a byte when idle (we=1); hold until busy clears.
// txd is idle-high; frame = start(0) + 8 data LSB-first + stop(1).
// ---------------------------------------------------------------------------
`timescale 1ns/1ps

module uart_tx #(
    parameter DIVISOR = 868          // clk_hz / baud (100 MHz / 115200)
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       we,
    output wire       busy,
    output wire       txd
);
    localparam [15:0] DIV = DIVISOR[15:0];

    reg [9:0]  shift;
    reg [15:0] baud_cnt;
    reg [3:0]  bit_cnt;               // 0=start, 1..8=data, 9=stop
    reg        active;

    assign busy = active;
    assign txd  = active ? shift[0] : 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            shift    <= 10'h3FF;
            baud_cnt <= 16'd0;
            bit_cnt  <= 4'd0;
            active   <= 1'b0;
        end else if (!active) begin
            if (we) begin
                shift    <= {1'b1, data, 1'b0};
                bit_cnt  <= 4'd0;
                baud_cnt <= 16'd0;
                active   <= 1'b1;
            end
        end else begin
            baud_cnt <= baud_cnt + 16'd1;
            if (baud_cnt == DIV - 16'd1) begin
                baud_cnt <= 16'd0;
                shift    <= {1'b1, shift[9:1]};
                bit_cnt  <= bit_cnt + 4'd1;
                if (bit_cnt == 4'd9)
                    active <= 1'b0;
            end
        end
    end
endmodule
