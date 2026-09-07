`timescale 1ns/1ps

// Simple DE0-Nano demo wrapper for the bridge-enabled system.
//
// Controls:
//   KEY[0]   : active-low reset
//   KEY[1]   : start one operation
//   SW[0]    : 0 = local access, 1 = remote access through Slave 4
//   SW[2:1]  : target slave ID
//              00=S1, 01=S2, 10=S3, 11=reserved/bridge
//   SW[3]    : 0 = write, 1 = read
//
// Address used in this board demo is memory location 12'h000.
//
// UART physical wiring between two boards:
//   this bridge_slave_uart_tx  -> other bridge_master_uart_rx
//   this bridge_slave_uart_rx  <- other bridge_master_uart_tx
//   this bridge_master_uart_tx -> other bridge_slave_uart_rx
//   this bridge_master_uart_rx <- other bridge_slave_uart_tx
//   GND                        <-> GND
module de0_nano_bridge_top (
    input  wire       CLOCK_50,
    input  wire [1:0] KEY,
    input  wire [3:0] SW,
    output wire [7:0] LED,

    input  wire bridge_master_uart_rx,
    output wire bridge_master_uart_tx,
    input  wire bridge_slave_uart_rx,
    output wire bridge_slave_uart_tx
);
    wire reset_n = KEY[0];

    reg start_meta;
    reg start_sync;
    reg start_previous;
    wire start_pulse = start_previous & ~start_sync;

    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            start_meta     <= 1'b1;
            start_sync     <= 1'b1;
            start_previous <= 1'b1;
        end
        else begin
            start_meta     <= KEY[1];
            start_sync     <= start_meta;
            start_previous <= start_sync;
        end
    end

    localparam [2:0] CONTROL_IDLE      = 3'd0,
                     CONTROL_START     = 3'd1,
                     CONTROL_WAIT_BUSY = 3'd2,
                     CONTROL_WAIT_DONE = 3'd3;

    reg [2:0] control_state;
    reg selected_remote;
    reg [1:0] selected_slave;
    reg selected_write;
    reg [7:0] led_result;

    // 00/01/10 are real memory slaves. 11 is bridge itself and is reserved
    // as a remote target to prevent bridge loops.
    wire target_invalid = (selected_slave == 2'b11);

    wire [15:0] local_address = {
        selected_slave,
        2'b00,
        12'h000
    };

    wire [15:0] remote_address = {
        2'b11,          // local Slave 4 = bridge
        selected_slave, // target slave on remote board
        12'h000
    };

    wire [15:0] selected_address = selected_remote ?
                                   remote_address : local_address;

    localparam [7:0] BOARD_TEST_PATTERN = 8'hA5;

    reg master1_start;
    wire master1_ready;
    wire [7:0] master1_read_data;

    wire master1_grant;
    wire master2_grant;
    wire master1_split;
    wire master2_split;
    wire slave1_ready;
    wire slave2_ready;
    wire slave3_ready;
    wire slave4_ready;
    wire slave3_split;

    always @(*) begin
        master1_start = 1'b0;
        if (control_state == CONTROL_START)
            master1_start = 1'b1;
    end

    always @(posedge CLOCK_50 or negedge reset_n) begin
        if (!reset_n) begin
            control_state   <= CONTROL_IDLE;
            selected_remote <= 1'b0;
            selected_slave  <= 2'd0;
            selected_write  <= 1'b0;
            led_result      <= 8'd0;
        end
        else begin
            case (control_state)
                CONTROL_IDLE: begin
                    if (start_pulse) begin
                        selected_remote <= SW[0];
                        selected_slave  <= SW[2:1];
                        selected_write  <= ~SW[3]; // SW3=0 write, SW3=1 read
                        led_result      <= 8'd0;

                        // Local S4 and remote S4 are not demo targets.
                        if (SW[2:1] == 2'b11) begin
                            led_result <= 8'hEE;
                            control_state <= CONTROL_IDLE;
                        end
                        else begin
                            control_state <= CONTROL_START;
                        end
                    end
                end

                CONTROL_START:
                    control_state <= CONTROL_WAIT_BUSY;

                CONTROL_WAIT_BUSY: begin
                    if (!master1_ready)
                        control_state <= CONTROL_WAIT_DONE;
                end

                CONTROL_WAIT_DONE: begin
                    if (master1_ready) begin
                        if (target_invalid)
                            led_result <= 8'hEE;
                        else if (selected_write)
                            led_result <= BOARD_TEST_PATTERN;
                        else
                            led_result <= master1_read_data;

                        control_state <= CONTROL_IDLE;
                    end
                end

                default: control_state <= CONTROL_IDLE;
            endcase
        end
    end

    integrated_system_bus_bridge #(
        .ADDR_WIDTH(16),
        .DATA_WIDTH(8),
        .SLAVE_MEM_ADDR_WIDTH(14),
        .UART_CLOCKS_PER_BIT(5208)
    ) system_inst (
        .clk(CLOCK_50),
        .reset_n(reset_n),
        .master1_write_data(BOARD_TEST_PATTERN),
        .master1_read_data(master1_read_data),
        .master1_address(selected_address),
        .master1_start(master1_start),
        .master1_ready(master1_ready),
        .master1_write(selected_write),
        .bridge_master_uart_rx(bridge_master_uart_rx),
        .bridge_master_uart_tx(bridge_master_uart_tx),
        .bridge_slave_uart_rx(bridge_slave_uart_rx),
        .bridge_slave_uart_tx(bridge_slave_uart_tx),
        .master1_grant_debug(master1_grant),
        .master2_grant_debug(master2_grant),
        .master1_split_debug(master1_split),
        .master2_split_debug(master2_split),
        .slave1_ready_debug(slave1_ready),
        .slave2_ready_debug(slave2_ready),
        .slave3_ready_debug(slave3_ready),
        .slave4_ready_debug(slave4_ready),
        .slave3_split_debug(slave3_split)
    );

    assign LED = led_result;
endmodule
