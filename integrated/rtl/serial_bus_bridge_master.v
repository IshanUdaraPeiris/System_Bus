`timescale 1ns/1ps

// Master-2 bus bridge endpoint.
// Receives a UART request from the remote team's bridge slave and converts it
// into a normal transaction on this system bus using serial_master_port.
//
// UART request frame:
//   { mode, data[7:0], bridge_address[13:0] }
// bridge_address:
//   [13:12] = target local slave on this bus
//   [11:0]  = memory address
//
// Remote slave ID 2'b11 is reserved here to prevent bridge-to-bridge loops.
// Invalid remote reads return 8'hEE; invalid remote writes are discarded.
module serial_bus_bridge_master #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 14,
    parameter BRIDGE_ADDR_WIDTH = 14,
    parameter UART_CLOCKS_PER_BIT = 5208
) (
    input  wire clk,
    input  wire reset_n,

    // Local system-bus master interface
    input  wire serial_read_data,
    output wire serial_write_data,
    output wire serial_write,
    output wire master_valid,
    input  wire slave_valid,
    output wire bus_request,
    input  wire bus_grant,
    input  wire split_active,
    input  wire address_ack,

    // UART interface to remote team's bridge slave
    output wire bridge_uart_tx,
    input  wire bridge_uart_rx
);
    localparam REQUEST_WIDTH = 1 + DATA_WIDTH + BRIDGE_ADDR_WIDTH;

    reg [DATA_WIDTH-1:0] device_write_data;
    wire [DATA_WIDTH-1:0] device_read_data;
    reg [BRIDGE_ADDR_WIDTH-1:0] bridge_address;
    wire [ADDR_WIDTH-1:0] device_address;
    reg device_write;
    wire device_ready;
    wire device_start;

    wire uart_tx_busy;
    wire uart_rx_ready;
    wire [REQUEST_WIDTH-1:0] uart_rx_data;
    reg [DATA_WIDTH-1:0] response_data;
    wire uart_response_start;

    reg pending_read;

    localparam [3:0] BM_IDLE              = 4'd0,
                     BM_WAIT_MASTER_READY = 4'd1,
                     BM_START_MASTER      = 4'd2,
                     BM_WAIT_MASTER_BUSY  = 4'd3,
                     BM_WAIT_MASTER_DONE  = 4'd4,
                     BM_TX_RESPONSE_START = 4'd5,
                     BM_TX_WAIT_BUSY      = 4'd6,
                     BM_TX_WAIT_DONE      = 4'd7;

    reg [3:0] bridge_state;

    bridge_addr_convert #(
        .BRIDGE_ADDR_WIDTH(BRIDGE_ADDR_WIDTH),
        .BUS_ADDR_WIDTH(ADDR_WIDTH)
    ) addr_convert_inst (
        .bridge_address(bridge_address),
        .bus_address(device_address)
    );

    assign device_start = (bridge_state == BM_START_MASTER);

    serial_master_port #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .SLAVE_MEM_ADDR_WIDTH(SLAVE_MEM_ADDR_WIDTH),
        .TIMEOUT_CYCLES(255)
    ) master_port_inst (
        .clk(clk),
        .reset_n(reset_n),
        .device_write_data(device_write_data),
        .device_read_data(device_read_data),
        .device_address(device_address),
        .device_start(device_start),
        .device_ready(device_ready),
        .device_write(device_write),
        .serial_read_data(serial_read_data),
        .serial_write_data(serial_write_data),
        .serial_write(serial_write),
        .master_valid(master_valid),
        .slave_valid(slave_valid),
        .bus_request(bus_request),
        .bus_grant(bus_grant),
        .split_active(split_active),
        .address_ack(address_ack)
    );

    assign uart_response_start =
        (bridge_state == BM_TX_RESPONSE_START) && !uart_tx_busy;

    bridge_uart #(
        .CLOCKS_PER_BIT(UART_CLOCKS_PER_BIT),
        .TX_DATA_WIDTH(DATA_WIDTH),
        .RX_DATA_WIDTH(REQUEST_WIDTH)
    ) uart_inst (
        .clk(clk),
        .reset_n(reset_n),
        .data_input(response_data),
        .data_en(uart_response_start),
        .tx(bridge_uart_tx),
        .tx_busy(uart_tx_busy),
        .rx(bridge_uart_rx),
        .ready(uart_rx_ready),
        .data_output(uart_rx_data)
    );

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            bridge_state      <= BM_IDLE;
            device_write_data <= {DATA_WIDTH{1'b0}};
            bridge_address    <= {BRIDGE_ADDR_WIDTH{1'b0}};
            device_write      <= 1'b0;
            pending_read      <= 1'b0;
            response_data     <= {DATA_WIDTH{1'b0}};
        end
        else begin
            case (bridge_state)
                BM_IDLE: begin
                    if (uart_rx_ready) begin
                        bridge_address <= uart_rx_data[BRIDGE_ADDR_WIDTH-1:0];
                        device_write_data <= uart_rx_data[
                            BRIDGE_ADDR_WIDTH +: DATA_WIDTH
                        ];
                        device_write <= uart_rx_data[
                            BRIDGE_ADDR_WIDTH + DATA_WIDTH
                        ];
                        pending_read <= !uart_rx_data[
                            BRIDGE_ADDR_WIDTH + DATA_WIDTH
                        ];

                        // ID 3 is this system's own bridge slave. Do not route
                        // a remote transaction back into another bridge hop.
                        if (uart_rx_data[13:12] == 2'b11) begin
                            if (!uart_rx_data[BRIDGE_ADDR_WIDTH + DATA_WIDTH]) begin
                                response_data <= 8'hEE;
                                bridge_state <= BM_TX_RESPONSE_START;
                            end
                            else begin
                                bridge_state <= BM_IDLE;
                            end
                        end
                        else begin
                            bridge_state <= BM_WAIT_MASTER_READY;
                        end
                    end
                end

                BM_WAIT_MASTER_READY: begin
                    if (device_ready)
                        bridge_state <= BM_START_MASTER;
                end

                BM_START_MASTER: begin
                    // device_start is high throughout this state, so the normal
                    // serial_master_port captures the request on this edge.
                    bridge_state <= BM_WAIT_MASTER_BUSY;
                end

                BM_WAIT_MASTER_BUSY: begin
                    if (!device_ready)
                        bridge_state <= BM_WAIT_MASTER_DONE;
                end

                BM_WAIT_MASTER_DONE: begin
                    if (device_ready) begin
                        if (pending_read) begin
                            response_data <= device_read_data;
                            bridge_state <= BM_TX_RESPONSE_START;
                        end
                        else begin
                            bridge_state <= BM_IDLE;
                        end
                    end
                end

                BM_TX_RESPONSE_START: begin
                    if (!uart_tx_busy)
                        bridge_state <= BM_TX_WAIT_BUSY;
                end

                BM_TX_WAIT_BUSY: begin
                    if (uart_tx_busy)
                        bridge_state <= BM_TX_WAIT_DONE;
                end

                BM_TX_WAIT_DONE: begin
                    if (!uart_tx_busy) begin
                        pending_read <= 1'b0;
                        bridge_state <= BM_IDLE;
                    end
                end

                default: bridge_state <= BM_IDLE;
            endcase
        end
    end
endmodule
