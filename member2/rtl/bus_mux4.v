`timescale 1ns/1ps

// Four-input combinational multiplexer used for four slave return paths.
module bus_mux4 #(
    parameter WIDTH = 1
) (
    input  wire [WIDTH-1:0] data0,
    input  wire [WIDTH-1:0] data1,
    input  wire [WIDTH-1:0] data2,
    input  wire [WIDTH-1:0] data3,
    input  wire [1:0]       select,
    output reg  [WIDTH-1:0] data_out
);
    always @(*) begin
        case (select)
            2'd0: data_out = data0;
            2'd1: data_out = data1;
            2'd2: data_out = data2;
            2'd3: data_out = data3;
            default: data_out = {WIDTH{1'b0}};
        endcase
    end
endmodule
