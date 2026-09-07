`timescale 1ns/1ps

// Two complete bridge-enabled buses connected exactly as two DE0-Nano boards
// would be connected. UART is accelerated for simulation by using 8 clocks/bit.
module tb_bridge_loop;
    localparam ADDR_WIDTH = 16;
    localparam DATA_WIDTH = 8;
    localparam UART_CLOCKS_PER_BIT = 8;

    reg clk;
    reg reset_n;

    // Bus A Master 1 device-side signals
    reg  [7:0]  a_wdata;
    wire [7:0]  a_rdata;
    reg  [15:0] a_addr;
    reg         a_start;
    wire        a_ready;
    reg         a_write;

    // Bus B Master 1 device-side signals
    reg  [7:0]  b_wdata;
    wire [7:0]  b_rdata;
    reg  [15:0] b_addr;
    reg         b_start;
    wire        b_ready;
    reg         b_write;

    // Bridge UART wires
    wire a_master_tx;
    wire a_slave_tx;
    wire b_master_tx;
    wire b_slave_tx;

    // Address helpers:
    // local:  {local_slave, 2'b00, mem[11:0]}
    // remote: {2'b11, remote_slave, mem[11:0]}
    function automatic [15:0] local_addr;
        input [1:0] slave_id;
        input [11:0] mem_addr;
        begin
            local_addr = {slave_id, 2'b00, mem_addr};
        end
    endfunction

    function automatic [15:0] remote_addr;
        input [1:0] remote_slave_id;
        input [11:0] mem_addr;
        begin
            remote_addr = {2'b11, remote_slave_id, mem_addr};
        end
    endfunction

    integrated_system_bus_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(14),
        .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
    ) bus_a (
        .clk(clk),
        .reset_n(reset_n),
        .master1_write_data(a_wdata),
        .master1_read_data(a_rdata),
        .master1_address(a_addr),
        .master1_start(a_start),
        .master1_ready(a_ready),
        .master1_write(a_write),

        // A master endpoint talks to B slave endpoint.
        .bridge_master_uart_rx(b_slave_tx),
        .bridge_master_uart_tx(a_master_tx),

        // A slave endpoint talks to B master endpoint.
        .bridge_slave_uart_rx(b_master_tx),
        .bridge_slave_uart_tx(a_slave_tx),

        .master1_grant_debug(),
        .master2_grant_debug(),
        .master1_split_debug(),
        .master2_split_debug(),
        .slave1_ready_debug(),
        .slave2_ready_debug(),
        .slave3_ready_debug(),
        .slave4_ready_debug(),
        .slave3_split_debug()
    );

    integrated_system_bus_bridge #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(14),
        .UART_CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT)
    ) bus_b (
        .clk(clk),
        .reset_n(reset_n),
        .master1_write_data(b_wdata),
        .master1_read_data(b_rdata),
        .master1_address(b_addr),
        .master1_start(b_start),
        .master1_ready(b_ready),
        .master1_write(b_write),

        .bridge_master_uart_rx(a_slave_tx),
        .bridge_master_uart_tx(b_master_tx),
        .bridge_slave_uart_rx(a_master_tx),
        .bridge_slave_uart_tx(b_slave_tx),

        .master1_grant_debug(),
        .master2_grant_debug(),
        .master1_split_debug(),
        .master2_split_debug(),
        .slave1_ready_debug(),
        .slave2_ready_debug(),
        .slave3_ready_debug(),
        .slave4_ready_debug(),
        .slave3_split_debug()
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic a_write_txn;
        input [15:0] addr;
        input [7:0] data;
        begin
            wait (a_ready);
            @(negedge clk);
            a_addr  = addr;
            a_wdata = data;
            a_write = 1'b1;
            a_start = 1'b1;
            @(negedge clk);
            a_start = 1'b0;
            wait (!a_ready);
            wait (a_ready);
            @(negedge clk);
        end
    endtask

    task automatic a_read_txn;
        input [15:0] addr;
        output [7:0] data;
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

    task automatic b_write_txn;
        input [15:0] addr;
        input [7:0] data;
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

    task automatic b_read_txn;
        input [15:0] addr;
        output [7:0] data;
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

    reg [7:0] check_data;

    initial begin
        reset_n = 1'b0;
        a_wdata = 8'h00;
        a_addr  = 16'h0000;
        a_start = 1'b0;
        a_write = 1'b0;
        b_wdata = 8'h00;
        b_addr  = 16'h0000;
        b_start = 1'b0;
        b_write = 1'b0;

        repeat (5) @(posedge clk);
        reset_n = 1'b1;
        repeat (5) @(posedge clk);

        // --------------------------------------------------
        // 1) Bus A writes through S4 bridge into Bus B Slave 1.
        // --------------------------------------------------
        $display("TEST 1: A remote write -> B Slave1");
        a_write_txn(remote_addr(2'b00, 12'h020), 8'hA5);

        // Read B Slave1 locally to verify the remote write.
        b_read_txn(local_addr(2'b00, 12'h020), check_data);
        if (check_data !== 8'hA5)
            $fatal(1, "Remote write failed: expected A5, got %02h", check_data);
        else
            $display("PASS: remote write A->B");

        // --------------------------------------------------
        // 2) Prepare Bus B Slave2 locally, then read it remotely from A.
        // --------------------------------------------------
        $display("TEST 2: A remote read <- B Slave2");
        b_write_txn(local_addr(2'b01, 12'h055), 8'h3C);
        a_read_txn(remote_addr(2'b01, 12'h055), check_data);
        if (check_data !== 8'h3C)
            $fatal(1, "Remote read failed: expected 3C, got %02h", check_data);
        else
            $display("PASS: remote read A<-B");

        // --------------------------------------------------
        // 3) Reverse direction: B writes through its bridge into A Slave3.
        // --------------------------------------------------
        $display("TEST 3: B remote write -> A Slave3");
        b_write_txn(remote_addr(2'b10, 12'h010), 8'h5A);
        a_read_txn(local_addr(2'b10, 12'h010), check_data);
        if (check_data !== 8'h5A)
            $fatal(1, "Reverse remote write failed: expected 5A, got %02h", check_data);
        else
            $display("PASS: remote write B->A");

        // --------------------------------------------------
        // 4) Reverse remote read.
        // --------------------------------------------------
        a_write_txn(local_addr(2'b00, 12'h033), 8'hC7);
        b_read_txn(remote_addr(2'b00, 12'h033), check_data);
        if (check_data !== 8'hC7)
            $fatal(1, "Reverse remote read failed: expected C7, got %02h", check_data);
        else
            $display("PASS: remote read B<-A");

        $display("ALL BRIDGE LOOP TESTS PASSED");
        #100;
        $finish;
    end
endmodule
