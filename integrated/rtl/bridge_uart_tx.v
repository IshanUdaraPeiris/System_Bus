`timescale 1ns/1ps

// Generic UART transmitter: 1 start bit, DATA_WIDTH data bits LSB-first,
// 1 stop bit, no parity.
module bridge_uart_tx #(
    parameter CLOCKS_PER_BIT = 5208,
    parameter DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  reset_n,
    input  wire [DATA_WIDTH-1:0] data_in,
    input  wire                  data_en,
    output reg                   tx,
    output wire                  tx_busy
);
    localparam [1:0] TX_IDLE  = 2'd0,
                     TX_START = 2'd1,
                     TX_DATA  = 2'd2,
                     TX_STOP  = 2'd3;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] data_reg;
    integer clock_count;
    integer bit_index;

    assign tx_busy = (state != TX_IDLE);

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state       <= TX_IDLE;
            data_reg    <= {DATA_WIDTH{1'b0}};
            clock_count <= 0;
            bit_index   <= 0;
            tx          <= 1'b1;
        end
        else begin
            case (state)
                TX_IDLE: begin
                    tx          <= 1'b1;
                    clock_count <= 0;
                    bit_index   <= 0;
                    if (data_en) begin
                        data_reg <= data_in;
                        state    <= TX_START;
                    end
                end

                TX_START: begin
                    tx <= 1'b0;
                    if (clock_count == CLOCKS_PER_BIT-1) begin
                        clock_count <= 0;
                        bit_index   <= 0;
                        state       <= TX_DATA;
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                TX_DATA: begin
                    tx <= data_reg[bit_index];
                    if (clock_count == CLOCKS_PER_BIT-1) begin
                        clock_count <= 0;
                        if (bit_index == DATA_WIDTH-1) begin
                            state <= TX_STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                TX_STOP: begin
                    tx <= 1'b1;
                    if (clock_count == CLOCKS_PER_BIT-1) begin
                        clock_count <= 0;
                        state       <= TX_IDLE;
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                default: state <= TX_IDLE;
            endcase
        end
    end
endmodule
