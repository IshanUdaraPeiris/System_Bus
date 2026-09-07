`timescale 1ns/1ps

// Byte-addressed synchronous memory. The array is deliberately not reset so
// Quartus can map it into Cyclone IV embedded RAM.
module serial_slave_memory #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter MEM_BYTES = 4096
) (
    input  wire                  clk,
    input  wire                  reset_n,
    input  wire                  write_enable,
    input  wire                  read_enable,
    input  wire [ADDR_WIDTH-1:0] address,
    input  wire [DATA_WIDTH-1:0] write_data,
    output wire [DATA_WIDTH-1:0] read_data,
    output reg                   read_valid
);
    localparam MEMORY_ADDR_WIDTH = $clog2(MEM_BYTES);

    reg [DATA_WIDTH-1:0] memory [0:MEM_BYTES-1];
    reg [DATA_WIDTH-1:0] memory_read_register;
    wire [MEMORY_ADDR_WIDTH-1:0] memory_address;
    wire address_in_range;

    assign memory_address = address[MEMORY_ADDR_WIDTH-1:0];
    assign address_in_range = (address < MEM_BYTES);
    assign read_data = address_in_range ? memory_read_register :
                                             {DATA_WIDTH{1'b0}};

    // Keep memory access and its data output in one clocked process so Quartus
    // infers a synchronous embedded RAM instead of thousands of logic cells.
    // Embedded RAM data registers do not support asynchronous clear; validity
    // and every protocol/control register still use the required async reset.
    always @(posedge clk) begin
        if (write_enable && address_in_range)
            memory[memory_address] <= write_data;
        if (read_enable && address_in_range)
            memory_read_register <= memory[memory_address];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            read_valid <= 1'b0;
        else
            read_valid <= read_enable;
    end
endmodule
