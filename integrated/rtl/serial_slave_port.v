`timescale 1ns/1ps

// Serial slave protocol controller based on the Anuki reference state flow.
// It receives local address and write-data fields LSB first and serializes read
// data LSB first. SPLIT_CAPABLE should be enabled only for Slave 3.
module serial_slave_port #(
    parameter ADDR_WIDTH = 12,
    parameter DATA_WIDTH = 8,
    parameter SPLIT_CAPABLE = 0,
    parameter SPLIT_DELAY_CYCLES = 4
) (
    input  wire                  clk,
    input  wire                  reset_n,

    input  wire [DATA_WIDTH-1:0] memory_read_data,
    input  wire                  memory_read_valid,
    output wire                  memory_write_enable,
    output wire                  memory_read_enable,
    output wire [ADDR_WIDTH-1:0] memory_address,
    output wire [DATA_WIDTH-1:0] memory_write_data,

    input  wire                  serial_write_data,
    output wire                  serial_read_data,
    input  wire                  serial_write,
    input  wire                  master_valid,
    input  wire                  split_resume,
    output wire                  slave_valid,
    output wire                  slave_ready,
    output wire                  split_request
);
    localparam [2:0] STATE_IDLE          = 3'd0,
                     STATE_ADDRESS       = 3'd1,
                     STATE_WRITE_DATA    = 3'd2,
                     STATE_START_ACCESS  = 3'd3,
                     STATE_WAIT_READ     = 3'd4,
                     STATE_SPLIT_DELAY   = 3'd5,
                     STATE_WAIT_RESUME   = 3'd6,
                     STATE_SEND_READ     = 3'd7;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [ADDR_WIDTH-1:0] address_buffer;
    reg [DATA_WIDTH-1:0] write_buffer;
    reg [DATA_WIDTH-1:0] read_buffer;
    reg write_mode;
    reg read_data_ready;
    reg [7:0] bit_count;
    reg [7:0] split_count;

    assign slave_ready        = (state == STATE_IDLE);
    assign split_request      = (state == STATE_SPLIT_DELAY);
    assign slave_valid        = (state == STATE_SEND_READ);
    assign serial_read_data   = slave_valid ? read_buffer[bit_count] : 1'b0;
    assign memory_address     = address_buffer;
    assign memory_write_data  = write_buffer;
    assign memory_write_enable = (state == STATE_START_ACCESS) && write_mode;
    assign memory_read_enable  = (state == STATE_START_ACCESS) && !write_mode;

    always @(*) begin
        case (state)
            STATE_IDLE:
                next_state = master_valid ? STATE_ADDRESS : STATE_IDLE;

            STATE_ADDRESS:
                next_state = (master_valid && (bit_count == ADDR_WIDTH-1)) ?
                             (write_mode ? STATE_WRITE_DATA : STATE_START_ACCESS) :
                             STATE_ADDRESS;

            STATE_WRITE_DATA:
                next_state = (master_valid && (bit_count == DATA_WIDTH-1)) ?
                             STATE_START_ACCESS : STATE_WRITE_DATA;

            STATE_START_ACCESS:
                next_state = write_mode ? STATE_IDLE :
                             (SPLIT_CAPABLE ? STATE_SPLIT_DELAY : STATE_WAIT_READ);

            STATE_WAIT_READ:
                next_state = memory_read_valid ? STATE_SEND_READ : STATE_WAIT_READ;

            STATE_SPLIT_DELAY:
                next_state = (split_count >= SPLIT_DELAY_CYCLES-1) ?
                             STATE_WAIT_RESUME : STATE_SPLIT_DELAY;

            STATE_WAIT_RESUME:
                next_state = (split_resume && read_data_ready) ?
                             STATE_SEND_READ : STATE_WAIT_RESUME;

            STATE_SEND_READ:
                next_state = (bit_count == DATA_WIDTH-1) ? STATE_IDLE : STATE_SEND_READ;

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
            address_buffer <= {ADDR_WIDTH{1'b0}};
            write_buffer   <= {DATA_WIDTH{1'b0}};
            read_buffer    <= {DATA_WIDTH{1'b0}};
            write_mode     <= 1'b0;
            read_data_ready <= 1'b0;
            bit_count      <= 8'd0;
            split_count    <= 8'd0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    bit_count       <= 8'd0;
                    split_count     <= 8'd0;
                    read_data_ready <= 1'b0;
                    if (master_valid) begin
                        write_mode       <= serial_write;
                        address_buffer[0] <= serial_write_data;
                        bit_count        <= 8'd1;
                    end
                end

                STATE_ADDRESS: begin
                    if (master_valid) begin
                        address_buffer[bit_count] <= serial_write_data;
                        if (bit_count == ADDR_WIDTH-1)
                            bit_count <= 8'd0;
                        else
                            bit_count <= bit_count + 1'b1;
                    end
                end

                STATE_WRITE_DATA: begin
                    if (master_valid) begin
                        write_buffer[bit_count] <= serial_write_data;
                        if (bit_count == DATA_WIDTH-1)
                            bit_count <= 8'd0;
                        else
                            bit_count <= bit_count + 1'b1;
                    end
                end

                STATE_START_ACCESS: begin
                    bit_count <= 8'd0;
                end

                STATE_WAIT_READ: begin
                    if (memory_read_valid) begin
                        read_buffer     <= memory_read_data;
                        read_data_ready <= 1'b1;
                    end
                end

                STATE_SPLIT_DELAY: begin
                    if (split_count < SPLIT_DELAY_CYCLES-1)
                        split_count <= split_count + 1'b1;
                    if (memory_read_valid) begin
                        read_buffer     <= memory_read_data;
                        read_data_ready <= 1'b1;
                    end
                end

                STATE_WAIT_RESUME: begin
                    split_count <= 8'd0;
                    if (memory_read_valid) begin
                        read_buffer     <= memory_read_data;
                        read_data_ready <= 1'b1;
                    end
                end

                STATE_SEND_READ: begin
                    if (bit_count == DATA_WIDTH-1)
                        bit_count <= 8'd0;
                    else
                        bit_count <= bit_count + 1'b1;
                end

                default: begin
                    bit_count   <= 8'd0;
                    split_count <= 8'd0;
                end
            endcase
        end
    end
endmodule
