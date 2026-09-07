`timescale 1ns/1ps

module serial_bus_slave #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter MEM_BYTES = 4096,
    parameter SPLIT_CAPABLE = 0,
    parameter SPLIT_DELAY_CYCLES = 4
) (
    input  wire clk,
    input  wire reset_n,
    input  wire serial_write_data,
    output wire serial_read_data,
    input  wire serial_write,
    input  wire master_valid,
    input  wire split_resume,
    output wire slave_valid,
    output wire slave_ready,
    output wire split_request
);
    wire [DATA_WIDTH-1:0] memory_read_data;
    wire [DATA_WIDTH-1:0] memory_write_data;
    wire [ADDR_WIDTH-1:0] memory_address;
    wire memory_write_enable;
    wire memory_read_enable;
    wire memory_read_valid;

    serial_slave_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPLIT_CAPABLE(SPLIT_CAPABLE),
        .SPLIT_DELAY_CYCLES(SPLIT_DELAY_CYCLES)
    ) port_inst (
        .clk(clk),
        .reset_n(reset_n),
        .memory_read_data(memory_read_data),
        .memory_read_valid(memory_read_valid),
        .memory_write_enable(memory_write_enable),
        .memory_read_enable(memory_read_enable),
        .memory_address(memory_address),
        .memory_write_data(memory_write_data),
        .serial_write_data(serial_write_data),
        .serial_read_data(serial_read_data),
        .serial_write(serial_write),
        .master_valid(master_valid),
        .split_resume(split_resume),
        .slave_valid(slave_valid),
        .slave_ready(slave_ready),
        .split_request(split_request)
    );

    serial_slave_memory #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_BYTES(MEM_BYTES)
    ) memory_inst (
        .clk(clk),
        .reset_n(reset_n),
        .write_enable(memory_write_enable),
        .read_enable(memory_read_enable),
        .address(memory_address),
        .write_data(memory_write_data),
        .read_data(memory_read_data),
        .read_valid(memory_read_valid)
    );
endmodule
