`timescale 1ns/1ps

// Converts a parallel device request into the assignment's one-bit serial
// master protocol. The transfer order follows the Anuki reference design:
// device ID, local address, then write data (all LSB first).
module serial_master_port #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 8,
    parameter SLAVE_MEM_ADDR_WIDTH = 12,
    parameter TIMEOUT_CYCLES = 8
) (
    input  wire                  clk,
    input  wire                  reset_n,

    input  wire [DATA_WIDTH-1:0] device_write_data,
    output wire [DATA_WIDTH-1:0] device_read_data,
    input  wire [ADDR_WIDTH-1:0] device_address,
    input  wire                  device_start,
    output wire                  device_ready,
    input  wire                  device_write,

    input  wire                  serial_read_data,
    output reg                   serial_write_data,
    output wire                  serial_write,
    output reg                   master_valid,
    input  wire                  slave_valid,

    output wire                  bus_request,
    input  wire                  bus_grant,
    input  wire                  split_active,
    input  wire                  address_ack
);
    localparam DEVICE_ADDR_WIDTH = ADDR_WIDTH - SLAVE_MEM_ADDR_WIDTH;

    localparam [2:0] STATE_IDLE       = 3'd0,
                     STATE_REQUEST    = 3'd1,
                     STATE_DEVICE_ID  = 3'd2,
                     STATE_WAIT_ACK   = 3'd3,
                     STATE_ADDRESS    = 3'd4,
                     STATE_WRITE_DATA = 3'd5,
                     STATE_READ_DATA  = 3'd6,
                     STATE_SPLIT_WAIT = 3'd7;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [ADDR_WIDTH-1:0] address_buffer;
    reg [DATA_WIDTH-1:0] write_buffer;
    reg [DATA_WIDTH-1:0] read_buffer;
    reg write_mode;
    reg [7:0] bit_count;
    reg [7:0] timeout_count;

    assign device_ready     = (state == STATE_IDLE);
    assign device_read_data = read_buffer;
    assign serial_write     = write_mode;
    assign bus_request      = (state != STATE_IDLE);

    always @(*) begin
        case (state)
            STATE_IDLE:
                next_state = device_start ? STATE_REQUEST : STATE_IDLE;

            STATE_REQUEST:
                next_state = bus_grant ? STATE_DEVICE_ID : STATE_REQUEST;

            STATE_DEVICE_ID:
                next_state = (bit_count == DEVICE_ADDR_WIDTH-1) ?
                             STATE_WAIT_ACK : STATE_DEVICE_ID;

            STATE_WAIT_ACK:
                next_state = address_ack ? STATE_ADDRESS :
                             ((timeout_count >= TIMEOUT_CYCLES) ?
                              STATE_IDLE : STATE_WAIT_ACK);

            STATE_ADDRESS:
                next_state = (bit_count == SLAVE_MEM_ADDR_WIDTH-1) ?
                             (write_mode ? STATE_WRITE_DATA : STATE_READ_DATA) :
                             STATE_ADDRESS;

            STATE_WRITE_DATA:
                next_state = (bit_count == DATA_WIDTH-1) ?
                             STATE_IDLE : STATE_WRITE_DATA;

            STATE_READ_DATA:
                next_state = split_active ? STATE_SPLIT_WAIT :
                             ((slave_valid && (bit_count == DATA_WIDTH-1)) ?
                              STATE_IDLE : STATE_READ_DATA);

            STATE_SPLIT_WAIT:
                next_state = (!split_active && bus_grant) ?
                             STATE_READ_DATA : STATE_SPLIT_WAIT;

            default: next_state = STATE_IDLE;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            state <= STATE_IDLE;
        else
            state <= next_state;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            address_buffer   <= {ADDR_WIDTH{1'b0}};
            write_buffer     <= {DATA_WIDTH{1'b0}};
            read_buffer      <= {DATA_WIDTH{1'b0}};
            write_mode       <= 1'b0;
            bit_count        <= 8'd0;
            timeout_count    <= 8'd0;
            serial_write_data <= 1'b0;
            master_valid     <= 1'b0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    bit_count     <= 8'd0;
                    timeout_count <= 8'd0;
                    master_valid  <= 1'b0;

                    if (device_start) begin
                        address_buffer <= device_address;
                        write_buffer   <= device_write_data;
                        write_mode     <= device_write;
                    end
                end

                STATE_REQUEST: begin
                    master_valid <= 1'b0;
                end

                STATE_DEVICE_ID: begin
                    serial_write_data <=
                        address_buffer[SLAVE_MEM_ADDR_WIDTH + bit_count];
                    master_valid <= 1'b1;

                    if (bit_count == DEVICE_ADDR_WIDTH-1)
                        bit_count <= 8'd0;
                    else
                        bit_count <= bit_count + 1'b1;
                end

                STATE_WAIT_ACK: begin
                    master_valid <= 1'b0;
                    if (timeout_count < TIMEOUT_CYCLES)
                        timeout_count <= timeout_count + 1'b1;
                end

                STATE_ADDRESS: begin
                    serial_write_data <= address_buffer[bit_count];
                    master_valid <= 1'b1;

                    if (bit_count == SLAVE_MEM_ADDR_WIDTH-1)
                        bit_count <= 8'd0;
                    else
                        bit_count <= bit_count + 1'b1;
                end

                STATE_WRITE_DATA: begin
                    serial_write_data <= write_buffer[bit_count];
                    master_valid <= 1'b1;

                    if (bit_count == DATA_WIDTH-1)
                        bit_count <= 8'd0;
                    else
                        bit_count <= bit_count + 1'b1;
                end

                STATE_READ_DATA: begin
                    master_valid <= 1'b0;
                    if (slave_valid) begin
                        read_buffer[bit_count] <= serial_read_data;
                        if (bit_count == DATA_WIDTH-1)
                            bit_count <= 8'd0;
                        else
                            bit_count <= bit_count + 1'b1;
                    end
                end

                STATE_SPLIT_WAIT: begin
                    master_valid <= 1'b0;
                end

                default: begin
                    master_valid <= 1'b0;
                    bit_count    <= 8'd0;
                end
            endcase
        end
    end
endmodule
