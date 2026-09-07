`timescale 1ns/1ps

// Slave-4 bus bridge endpoint.
// To the local bus it behaves like a normal serial slave.
// Instead of accessing RAM, it forwards the transaction through UART.
//
// Local address received by this slave is 14 bits:
//   [13:12] = target slave ID on the remote bus
//   [11:0]  = target memory address
//
// UART request frame:
//   { mode, data[7:0], bridge_address[13:0] }
//   mode=0 read, mode=1 write
// UART read response:
//   data[7:0]
module serial_bus_bridge_slave #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 14,
    parameter UART_CLOCKS_PER_BIT = 5208
) (
    input  wire clk,
    input  wire reset_n,

    // Local serial bus interface
    input  wire serial_write_data,
    output wire serial_read_data,
    input  wire serial_write,
    input  wire master_valid,
    input  wire split_resume,
    output wire slave_valid,
    output wire slave_ready,
    output wire split_request,

    // UART interface to the remote team's bridge master
    output wire bridge_uart_tx,
    input  wire bridge_uart_rx
);
    localparam REQUEST_WIDTH = 1 + DATA_WIDTH + ADDR_WIDTH;

    // Signals that normally connect serial_slave_port to memory.
    wire [DATA_WIDTH-1:0] memory_read_data;
    wire [DATA_WIDTH-1:0] memory_write_data;
    wire [ADDR_WIDTH-1:0] memory_address;
    wire memory_write_enable;
    wire memory_read_enable;
    wire memory_read_valid;
    wire port_ready;

    reg [REQUEST_WIDTH-1:0] request_data;
    reg request_is_read;
    reg [DATA_WIDTH-1:0] remote_read_data;

    wire uart_tx_busy;
    wire uart_rx_ready;
    wire [DATA_WIDTH-1:0] uart_rx_data;
    wire uart_tx_start;

    localparam [2:0] BR_IDLE         = 3'd0,
                     BR_TX_START     = 3'd1,
                     BR_TX_WAIT_BUSY = 3'd2,
                     BR_TX_WAIT_DONE = 3'd3,
                     BR_READ_WAIT    = 3'd4,
                     BR_READ_VALID   = 3'd5;

    reg [2:0] bridge_state;

    // This bridge endpoint itself does not split. Slave 3 remains the only
    // split-capable local slave.
    serial_slave_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SPLIT_CAPABLE(0),
        .SPLIT_DELAY_CYCLES(4)
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
        .slave_ready(port_ready),
        .split_request(split_request)
    );

    assign memory_read_data  = remote_read_data;
    assign memory_read_valid = (bridge_state == BR_READ_VALID);

    // Do not advertise the bridge as ready while its UART-side operation is
    // still active, even if serial_slave_port has already returned to IDLE.
    assign slave_ready = port_ready && (bridge_state == BR_IDLE);

    assign uart_tx_start = (bridge_state == BR_TX_START) && !uart_tx_busy;

    bridge_uart #(
        .CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT),
        .TX_DATA_WIDTH(REQUEST_WIDTH),
        .RX_DATA_WIDTH(DATA_WIDTH)
    ) uart_inst (
        .clk(clk),
        .reset_n(reset_n),
        .data_input(request_data),
        .data_en(uart_tx_start),
        .tx(bridge_uart_tx),
        .tx_busy(uart_tx_busy),
        .rx(bridge_uart_rx),
        .ready(uart_rx_ready),
        .data_output(uart_rx_data)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bridge_state   <= BR_IDLE;
            request_data   <= {REQUEST_WIDTH{1'b0}};
            request_is_read <= 1'b0;
            remote_read_data <= {DATA_WIDTH{1'b0}};
        end
        else begin
            case (bridge_state)
                BR_IDLE: begin
                    // One of these enables pulses when serial_slave_port reaches
                    // STATE_START_ACCESS.
                    if (memory_write_enable) begin
                        request_data <= {
                            1'b1,
                            memory_write_data,
                            memory_address
                        };
                        request_is_read <= 1'b0;
                        bridge_state <= BR_TX_START;
                    end
                    else if (memory_read_enable) begin
                        request_data <= {
                            1'b0,
                            {DATA_WIDTH{1'b0}},
                            memory_address
                        };
                        request_is_read <= 1'b1;
                        bridge_state <= BR_TX_START;
                    end
                end

                BR_TX_START: begin
                    if (!uart_tx_busy)
                        bridge_state <= BR_TX_WAIT_BUSY;
                end

                BR_TX_WAIT_BUSY: begin
                    if (uart_tx_busy)
                        bridge_state <= BR_TX_WAIT_DONE;
                end

                BR_TX_WAIT_DONE: begin
                    if (!uart_tx_busy) begin
                        if (request_is_read)
                            bridge_state <= BR_READ_WAIT;
                        else
                            bridge_state <= BR_IDLE;
                    end
                end

                BR_READ_WAIT: begin
                    if (uart_rx_ready) begin
                        remote_read_data <= uart_rx_data;
                        bridge_state <= BR_READ_VALID;
                    end
                end

                BR_READ_VALID: begin
                    // One full clock with memory_read_valid=1 is enough for
                    // serial_slave_port to copy the returned byte.
                    bridge_state <= BR_IDLE;
                end

                default: bridge_state <= BR_IDLE;
            endcase
        end
    end
endmodule
