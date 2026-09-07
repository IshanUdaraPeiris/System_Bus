`timescale 1ns/1ps

// Bridge-enabled system:
//   Master 1 = normal local master
//   Master 2 = UART bus-bridge master
//   Slave 1  = 2 KB memory
//   Slave 2  = 4 KB memory
//   Slave 3  = 4 KB split-capable memory
//   Slave 4  = UART bus-bridge slave
//
// 16-bit address format:
//   [15:14] local slave ID
//      00 = S1, 01 = S2, 10 = S3, 11 = S4 bridge
//   [13:12] remote slave ID (used when local ID = 11)
//   [11:0] memory address
module integrated_system_bus_bridge #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 14,
    parameter UART_CLOCKS_PER_BIT = 5208
) (
    input  wire                  clk,
    input  wire                  reset_n,

    // Normal local Master 1 device-side interface
    input  wire [DATA_WIDTH-1:0] master1_write_data,
    output wire [DATA_WIDTH-1:0] master1_read_data,
    input  wire [ADDR_WIDTH-1:0] master1_address,
    input  wire                  master1_start,
    output wire                  master1_ready,
    input  wire                  master1_write,

    // UART belonging to Master 2 bridge endpoint.
    // Connect this RX to the OTHER board's bridge-slave TX.
    // Connect this TX to the OTHER board's bridge-slave RX.
    input  wire                  bridge_master_uart_rx,
    output wire                  bridge_master_uart_tx,

    // UART belonging to Slave 4 bridge endpoint.
    // Connect this RX to the OTHER board's bridge-master TX.
    // Connect this TX to the OTHER board's bridge-master RX.
    input  wire                  bridge_slave_uart_rx,
    output wire                  bridge_slave_uart_tx,

    // Debug/status
    output wire                  master1_grant_debug,
    output wire                  master2_grant_debug,
    output wire                  master1_split_debug,
    output wire                  master2_split_debug,
    output wire                  slave1_ready_debug,
    output wire                  slave2_ready_debug,
    output wire                  slave3_ready_debug,
    output wire                  slave4_ready_debug,
    output wire                  slave3_split_debug
);
    // Master 1 serial wires
    wire m1_read_data;
    wire m1_write_data;
    wire m1_write_mode;
    wire m1_master_valid;
    wire m1_slave_valid;
    wire m1_request;
    wire m1_ack;

    // Master 2 bridge serial wires
    wire m2_read_data;
    wire m2_write_data;
    wire m2_write_mode;
    wire m2_master_valid;
    wire m2_slave_valid;
    wire m2_request;
    wire m2_ack;

    // Slave 1
    wire s1_read_data;
    wire s1_write_data;
    wire s1_write_mode;
    wire s1_master_valid;
    wire s1_slave_valid;

    // Slave 2
    wire s2_read_data;
    wire s2_write_data;
    wire s2_write_mode;
    wire s2_master_valid;
    wire s2_slave_valid;

    // Slave 3
    wire s3_read_data;
    wire s3_write_data;
    wire s3_write_mode;
    wire s3_master_valid;
    wire s3_slave_valid;

    // Slave 4 bridge
    wire s4_read_data;
    wire s4_write_data;
    wire s4_write_mode;
    wire s4_master_valid;
    wire s4_slave_valid;

    wire split_resume;

    // ----------------------------------------------------
    // Master 1: normal local master
    // ----------------------------------------------------
    serial_master_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH)
    ) master1_inst (
        .clk(clk),
        .reset_n(reset_n),
        .device_write_data(master1_write_data),
        .device_read_data(master1_read_data),
        .device_address(master1_address),
        .device_start(master1_start),
        .device_ready(master1_ready),
        .device_write(master1_write),
        .serial_read_data(m1_read_data),
        .serial_write_data(m1_write_data),
        .serial_write(m1_write_mode),
        .master_valid(m1_master_valid),
        .slave_valid(m1_slave_valid),
        .bus_request(m1_request),
        .bus_grant(master1_grant_debug),
        .split_active(master1_split_debug),
        .address_ack(m1_ack)
    );

    // ----------------------------------------------------
    // Master 2: receives remote UART requests and generates
    // normal transactions on this local bus.
    // ----------------------------------------------------
    serial_bus_bridge_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .BRIDGE_ADDR_WIDTH(14),
        .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
    ) master2_bridge_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_read_data(m2_read_data),
        .serial_write_data(m2_write_data),
        .serial_write(m2_write_mode),
        .master_valid(m2_master_valid),
        .slave_valid(m2_slave_valid),
        .bus_request(m2_request),
        .bus_grant(master2_grant_debug),
        .split_active(master2_split_debug),
        .address_ack(m2_ack),
        .bridge_uart_tx(bridge_master_uart_tx),
        .bridge_uart_rx(bridge_master_uart_rx)
    );

    // ----------------------------------------------------
    // Four-slave interconnect
    // ----------------------------------------------------
    serial_bus_m2_s4 #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH)
    ) interconnect_inst (
        .clk(clk),
        .reset_n(reset_n),

        .m1_rdata(m1_read_data),
        .m1_wdata(m1_write_data),
        .m1_mode(m1_write_mode),
        .m1_mvalid(m1_master_valid),
        .m1_svalid(m1_slave_valid),
        .m1_breq(m1_request),
        .m1_bgrant(master1_grant_debug),
        .m1_ack(m1_ack),
        .m1_split(master1_split_debug),

        .m2_rdata(m2_read_data),
        .m2_wdata(m2_write_data),
        .m2_mode(m2_write_mode),
        .m2_mvalid(m2_master_valid),
        .m2_svalid(m2_slave_valid),
        .m2_breq(m2_request),
        .m2_bgrant(master2_grant_debug),
        .m2_ack(m2_ack),
        .m2_split(master2_split_debug),

        .s1_rdata(s1_read_data),
        .s1_wdata(s1_write_data),
        .s1_mode(s1_write_mode),
        .s1_mvalid(s1_master_valid),
        .s1_svalid(s1_slave_valid),
        .s1_ready(slave1_ready_debug),

        .s2_rdata(s2_read_data),
        .s2_wdata(s2_write_data),
        .s2_mode(s2_write_mode),
        .s2_mvalid(s2_master_valid),
        .s2_svalid(s2_slave_valid),
        .s2_ready(slave2_ready_debug),

        .s3_rdata(s3_read_data),
        .s3_wdata(s3_write_data),
        .s3_mode(s3_write_mode),
        .s3_mvalid(s3_master_valid),
        .s3_svalid(s3_slave_valid),
        .s3_ready(slave3_ready_debug),
        .s3_split(slave3_split_debug),

        .s4_rdata(s4_read_data),
        .s4_wdata(s4_write_data),
        .s4_mode(s4_write_mode),
        .s4_mvalid(s4_master_valid),
        .s4_svalid(s4_slave_valid),
        .s4_ready(slave4_ready_debug),

        .split_grant(split_resume)
    );

    // ----------------------------------------------------
    // Slave 1: 2 KB
    // Local accesses must keep address[13:12] = 2'b00.
    // ----------------------------------------------------
    serial_bus_slave #(
        .ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_BYTES(2048),
        .SPLIT_CAPABLE(0)
    ) slave1_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_write_data(s1_write_data),
        .serial_read_data(s1_read_data),
        .serial_write(s1_write_mode),
        .master_valid(s1_master_valid),
        .split_resume(1'b0),
        .slave_valid(s1_slave_valid),
        .slave_ready(slave1_ready_debug),
        .split_request()
    );

    // ----------------------------------------------------
    // Slave 2: 4 KB
    // ----------------------------------------------------
    serial_bus_slave #(
        .ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_BYTES(4096),
        .SPLIT_CAPABLE(0)
    ) slave2_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_write_data(s2_write_data),
        .serial_read_data(s2_read_data),
        .serial_write(s2_write_mode),
        .master_valid(s2_master_valid),
        .split_resume(1'b0),
        .slave_valid(s2_slave_valid),
        .slave_ready(slave2_ready_debug),
        .split_request()
    );

    // ----------------------------------------------------
    // Slave 3: 4 KB, split-capable
    // ----------------------------------------------------
    serial_bus_slave #(
        .ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_BYTES(4096),
        .SPLIT_CAPABLE(1),
        .SPLIT_DELAY_CYCLES(4)
    ) slave3_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_write_data(s3_write_data),
        .serial_read_data(s3_read_data),
        .serial_write(s3_write_mode),
        .master_valid(s3_master_valid),
        .split_resume(split_resume),
        .slave_valid(s3_slave_valid),
        .slave_ready(slave3_ready_debug),
        .split_request(slave3_split_debug)
    );

    // ----------------------------------------------------
    // Slave 4: UART bus bridge
    // ----------------------------------------------------
    serial_bus_bridge_slave #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
    ) slave4_bridge_inst (
        .clk(clk),
        .reset_n(reset_n),
        .serial_write_data(s4_write_data),
        .serial_read_data(s4_read_data),
        .serial_write(s4_write_mode),
        .master_valid(s4_master_valid),
        .split_resume(1'b0),
        .slave_valid(s4_slave_valid),
        .slave_ready(slave4_ready_debug),
        .split_request(),
        .bridge_uart_tx(bridge_slave_uart_tx),
        .bridge_uart_rx(bridge_slave_uart_rx)
    );

endmodule
