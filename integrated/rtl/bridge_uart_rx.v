`timescale 1ns/1ps

// Generic UART receiver matching bridge_uart_tx.
// ready is a one-clock pulse when a complete word has been received.
module bridge_uart_rx #(
    parameter CLOCKS_PER_BIT = 5208,
    parameter DATA_WIDTH = 8
) (
    input  wire                  clk,
    input  wire                  reset_n,
    input  wire                  rx,
    output reg                   ready,
    output reg  [DATA_WIDTH-1:0] data_out
);
    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    reg [1:0] state;
    reg [DATA_WIDTH-1:0] data_reg;
    reg rx_meta;
    reg rx_sync;
    integer clock_count;
    integer bit_index;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end
        else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state       <= RX_IDLE;
            data_reg    <= {DATA_WIDTH{1'b0}};
            data_out    <= {DATA_WIDTH{1'b0}};
            ready       <= 1'b0;
            clock_count <= 0;
            bit_index   <= 0;
        end
        else begin
            ready <= 1'b0;

            case (state)
                RX_IDLE: begin
                    clock_count <= 0;
                    bit_index   <= 0;
                    if (!rx_sync)
                        state <= RX_START;
                end

                RX_START: begin
                    // Sample near the middle of the start bit.
                    if (clock_count == (CLOCKS_PER_BIT/2)-1) begin
                        clock_count <= 0;
                        if (!rx_sync) begin
                            bit_index <= 0;
                            state     <= RX_DATA;
                        end
                        else begin
                            state <= RX_IDLE; // false start
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                RX_DATA: begin
                    // One full bit period after the middle of the start bit
                    // lands near the middle of each data bit.
                    if (clock_count == CLOCKS_PER_BIT-1) begin
                        clock_count        <= 0;
                        data_reg[bit_index] <= rx_sync;

                        if (bit_index == DATA_WIDTH-1) begin
                            state <= RX_STOP;
                        end
                        else begin
                            bit_index <= bit_index + 1;
                        end
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                RX_STOP: begin
                    if (clock_count == CLOCKS_PER_BIT-1) begin
                        clock_count <= 0;
                        data_out    <= data_reg;
                        ready       <= 1'b1;
                        state       <= RX_IDLE;
                    end
                    else begin
                        clock_count <= clock_count + 1;
                    end
                end

                default: state <= RX_IDLE;
            endcase
        end
    end
endmodule
