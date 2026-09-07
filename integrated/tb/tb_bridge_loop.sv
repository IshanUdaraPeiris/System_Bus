`timescale 1ns/1ps

// Two complete bridge-enabled buses connected exactly as two DE0-Nano boards
// would be connected.
//
// UART is accelerated for simulation using 8 clocks/bit.
module tb_bridge_loop;

    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 8;
    localparam UART_CLOCKS_PER_BIT = 8;

    reg clk;
    reg reset_n;


    // ================================================================
    // Bus A - normal Master 1 device-side signals
    // ================================================================

    reg  [7:0]  a_wdata;
    wire [7:0]  a_rdata;
    reg  [15:0] a_addr;
    reg         a_start;
    wire        a_ready;
    reg         a_write;


    // ================================================================
    // Bus B - normal Master 1 device-side signals
    // ================================================================

    reg  [7:0]  b_wdata;
    wire [7:0]  b_rdata;
    reg  [15:0] b_addr;
    reg         b_start;
    wire        b_ready;
    reg         b_write;


    // ================================================================
    // UART connections
    // ================================================================

    wire a_master_tx;
    wire a_slave_tx;

    wire b_master_tx;
    wire b_slave_tx;


    // ================================================================
    // Debug signals
    //
    // Important:
    // A remote write from A appears as Master 2 activity on Bus B.
    //
    // A -> B remote transaction:
    //     watch b_master2_grant
    //
    // B -> A remote transaction:
    //     watch a_master2_grant
    // ================================================================

    wire a_master1_grant;
    wire a_master2_grant;

    wire b_master1_grant;
    wire b_master2_grant;

    wire a_master1_split;
    wire a_master2_split;

    wire b_master1_split;
    wire b_master2_split;

    wire a_slave1_ready;
    wire a_slave2_ready;
    wire a_slave3_ready;
    wire a_slave4_ready;

    wire b_slave1_ready;
    wire b_slave2_ready;
    wire b_slave3_ready;
    wire b_slave4_ready;

    wire a_slave3_split;
    wire b_slave3_split;


    // ================================================================
    // Address helper functions
    //
    // 16-bit address:
    //
    // [15:14] local slave
    // [13:12] remote slave
    // [11:0]  memory address
    //
    // Local:
    //     { local_slave, 00, address }
    //
    // Remote:
    //     { 11, remote_slave, address }
    //
    // 11 = local Slave 4 = bus bridge
    // ================================================================

    function automatic [15:0] local_addr;

        input [1:0]  slave_id;
        input [11:0] mem_addr;

        begin
            local_addr = {
                slave_id,
                2'b00,
                mem_addr
            };
        end

    endfunction


    function automatic [15:0] remote_addr;

        input [1:0]  remote_slave_id;
        input [11:0] mem_addr;

        begin
            remote_addr = {
                2'b11,            // local Slave 4 bridge
                remote_slave_id,  // target on remote bus
                mem_addr
            };
        end

    endfunction


    // ================================================================
    // BUS A
    // ================================================================

    integrated_system_bus_bridge #(

        .ADDR_WIDTH             (ADDR_WIDTH),
        .DATA_WIDTH             (DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH   (14),
        .UART_CLOCKS_PER_BIT    (UART_CLOCKS_PER_BIT)

    ) bus_a (

        .clk     (clk),
        .reset_n (reset_n),

        // Normal Master 1
        .master1_write_data (a_wdata),
        .master1_read_data  (a_rdata),
        .master1_address    (a_addr),
        .master1_start      (a_start),
        .master1_ready      (a_ready),
        .master1_write      (a_write),

        // A bridge master talks with B bridge slave
        .bridge_master_uart_rx (b_slave_tx),
        .bridge_master_uart_tx (a_master_tx),

        // A bridge slave talks with B bridge master
        .bridge_slave_uart_rx  (b_master_tx),
        .bridge_slave_uart_tx  (a_slave_tx),

        // Debug
        .master1_grant_debug (a_master1_grant),
        .master2_grant_debug (a_master2_grant),

        .master1_split_debug (a_master1_split),
        .master2_split_debug (a_master2_split),

        .slave1_ready_debug  (a_slave1_ready),
        .slave2_ready_debug  (a_slave2_ready),
        .slave3_ready_debug  (a_slave3_ready),
        .slave4_ready_debug  (a_slave4_ready),

        .slave3_split_debug  (a_slave3_split)
    );


    // ================================================================
    // BUS B
    // ================================================================

    integrated_system_bus_bridge #(

        .ADDR_WIDTH             (ADDR_WIDTH),
        .DATA_WIDTH             (DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH   (14),
        .UART_CLOCKS_PER_BIT    (UART_CLOCKS_PER_BIT)

    ) bus_b (

        .clk     (clk),
        .reset_n (reset_n),

        // Normal Master 1
        .master1_write_data (b_wdata),
        .master1_read_data  (b_rdata),
        .master1_address    (b_addr),
        .master1_start      (b_start),
        .master1_ready      (b_ready),
        .master1_write      (b_write),

        // B bridge master talks with A bridge slave
        .bridge_master_uart_rx (a_slave_tx),
        .bridge_master_uart_tx (b_master_tx),

        // B bridge slave talks with A bridge master
        .bridge_slave_uart_rx  (a_master_tx),
        .bridge_slave_uart_tx  (b_slave_tx),

        // Debug
        .master1_grant_debug (b_master1_grant),
        .master2_grant_debug (b_master2_grant),

        .master1_split_debug (b_master1_split),
        .master2_split_debug (b_master2_split),

        .slave1_ready_debug  (b_slave1_ready),
        .slave2_ready_debug  (b_slave2_ready),
        .slave3_ready_debug  (b_slave3_ready),
        .slave4_ready_debug  (b_slave4_ready),

        .slave3_split_debug  (b_slave3_split)
    );


    // ================================================================
    // Clock
    // ================================================================

    initial begin

        clk = 1'b0;

        forever #5 clk = ~clk;

    end


    // ================================================================
    // Bus A write
    // ================================================================

    task automatic a_write_txn;

        input [15:0] addr;
        input [7:0]  data;

        begin

            wait (a_ready);

            @(negedge clk);

            a_addr  = addr;
            a_wdata = data;
            a_write = 1'b1;
            a_start = 1'b1;

            @(negedge clk);

            a_start = 1'b0;

            // Master must first become busy.
            wait (!a_ready);

            // Then return to idle.
            wait (a_ready);

            @(negedge clk);

        end

    endtask


    // ================================================================
    // Bus A read
    // ================================================================

    task automatic a_read_txn;

        input  [15:0] addr;
        output [7:0]  data;

        begin

            wait (a_ready);

            @(negedge clk);

            a_addr  = addr;
            a_wdata = 8'h00;
            a_write = 1'b0;
            a_start = 1'b1;

            @(negedge clk);

            a_start = 1'b0;

            wait (!a_ready);

            wait (a_ready);

            @(negedge clk);

            data = a_rdata;

        end

    endtask


    // ================================================================
    // Bus B write
    // ================================================================

    task automatic b_write_txn;

        input [15:0] addr;
        input [7:0]  data;

        begin

            wait (b_ready);

            @(negedge clk);

            b_addr  = addr;
            b_wdata = data;
            b_write = 1'b1;
            b_start = 1'b1;

            @(negedge clk);

            b_start = 1'b0;

            wait (!b_ready);

            wait (b_ready);

            @(negedge clk);

        end

    endtask


    // ================================================================
    // Bus B read
    // ================================================================

    task automatic b_read_txn;

        input  [15:0] addr;
        output [7:0]  data;

        begin

            wait (b_ready);

            @(negedge clk);

            b_addr  = addr;
            b_wdata = 8'h00;
            b_write = 1'b0;
            b_start = 1'b1;

            @(negedge clk);

            b_start = 1'b0;

            wait (!b_ready);

            wait (b_ready);

            @(negedge clk);

            data = b_rdata;

        end

    endtask


    // ================================================================
    // Test data
    // ================================================================

    reg [7:0] check_data;


    // ================================================================
    // Main test sequence
    // ================================================================

    initial begin

        // ------------------------------------------------------------
        // Initial values
        // ------------------------------------------------------------

        reset_n = 1'b0;

        a_wdata = 8'h00;
        a_addr  = 16'h0000;
        a_start = 1'b0;
        a_write = 1'b0;

        b_wdata = 8'h00;
        b_addr  = 16'h0000;
        b_start = 1'b0;
        b_write = 1'b0;


        // ------------------------------------------------------------
        // Reset
        // ------------------------------------------------------------

        repeat (5)
            @(posedge clk);

        reset_n = 1'b1;

        repeat (5)
            @(posedge clk);


        // ============================================================
        // TEST 1
        //
        // Bus A Master 1
        //      ->
        // A Slave 4 bridge
        //      ->
        // UART
        //      ->
        //
