`timescale 1ns/1ps

// Full-duplex wrapper around the generic bridge UART transmitter/receiver.
module bridge_uart #(
    parameter CLOCKS_PER_BIT = 5208,
    parameter TX_DATA_WIDTH = 8,
    parameter RX_DATA_WIDTH = 8
) (
    input  wire                     clk,
    input  wire                     reset_n,
    input  wire [TX_DATA_WIDTH-1:0] data_input,
    input  wire                     data_en,
    output wire                     tx,
    output wire                     tx_busy,
    input  wire                     rx,
    output wire                     ready,
    output wire [RX_DATA_WIDTH-1:0] data_output
);
    bridge_uart_tx #(
        .CLOCKS_PER_BIT(CLOCKS_PER_BIT),
        .DATA_WIDTH(TX_DATA_WIDTH)
    ) tx_inst (
        .clk(clk),
        .reset_n(reset_n),
        .data_in(data_input),
        .data_en(data_en),
        .tx(tx),
        .tx_busy(tx_busy)
    );

    bridge_uart_rx #(
        .CLOCKS_PER_BIT(CLOCKS_PER_BIT),
        .DATA_WIDTH(RX_DATA_WIDTH)
    ) rx_inst (
        .clk(clk),
        .reset_n(reset_n),
        .rx(rx),
        .ready(ready),
        .data_out(data_output)
    );
endmodule
