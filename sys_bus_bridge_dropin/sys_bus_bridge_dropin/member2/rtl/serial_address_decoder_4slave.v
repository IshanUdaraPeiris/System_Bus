`timescale 1ns/1ps

// Four-slave version of the serial address decoder.
// Device IDs:
//   2'b00 = Slave 1
//   2'b01 = Slave 2
//   2'b10 = Slave 3 (split-capable)
//   2'b11 = Slave 4 (bus bridge slave)
module serial_address_decoder_4slave #(
    parameter DEVICE_ADDR_WIDTH = 2,
    parameter SPLIT_SLAVE_INDEX = 2
) (
    input  wire clk,
    input  wire reset_n,

    input  wire serial_data,
    input  wire master_valid,

    input  wire slave1_ready,
    input  wire slave2_ready,
    input  wire slave3_ready,
    input  wire slave4_ready,

    input  wire split_request,
    input  wire split_resume,

    output wire slave1_valid,
    output wire slave2_valid,
    output wire slave3_valid,
    output wire slave4_valid,
    output reg  [1:0] slave_select,
    output wire address_ack
);

    localparam [2:0] STATE_IDLE      = 3'd0,
                     STATE_DEVICE_ID = 3'd1,
                     STATE_ACK       = 3'd2,
                     STATE_TRANSFER  = 3'd3;

    localparam [1:0] SPLIT_SEL = SPLIT_SLAVE_INDEX;

    reg [2:0] state;
    reg [2:0] next_state;
    reg [DEVICE_ADDR_WIDTH-1:0] device_address;
    reg [7:0] bit_count;
    reg slave_busy_seen;
    reg split_pending;

    wire requested_address_valid;
    reg  requested_slave_ready;
    reg  selected_slave_ready;
    wire route_enable;

    assign requested_address_valid = (device_address < 4);
    assign address_ack = (state == STATE_ACK) &&
                         requested_address_valid &&
                         requested_slave_ready;
    assign route_enable = (state == STATE_TRANSFER);

    always @(*) begin
        case (device_address)
            0: requested_slave_ready = slave1_ready;
            1: requested_slave_ready = slave2_ready;
            2: requested_slave_ready = slave3_ready;
            3: requested_slave_ready = slave4_ready;
            default: requested_slave_ready = 1'b0;
        endcase
    end

    always @(*) begin
        case (slave_select)
            2'd0: selected_slave_ready = slave1_ready;
            2'd1: selected_slave_ready = slave2_ready;
            2'd2: selected_slave_ready = slave3_ready;
            2'd3: selected_slave_ready = slave4_ready;
            default: selected_slave_ready = 1'b0;
        endcase
    end

    bus_slave_valid_decoder4 valid_decoder (
        .slave_select(slave_select),
        .enable(master_valid & route_enable),
        .slave1_valid(slave1_valid),
        .slave2_valid(slave2_valid),
        .slave3_valid(slave3_valid),
        .slave4_valid(slave4_valid)
    );

    always @(*) begin
        next_state = state;

        case (state)
            STATE_IDLE: begin
                if (split_resume && split_pending)
                    next_state = STATE_TRANSFER;
                else if (master_valid) begin
                    if (DEVICE_ADDR_WIDTH == 1)
                        next_state = STATE_ACK;
                    else
                        next_state = STATE_DEVICE_ID;
                end
                else
                    next_state = STATE_IDLE;
            end

            STATE_DEVICE_ID: begin
                if (master_valid && (bit_count == DEVICE_ADDR_WIDTH-1))
                    next_state = STATE_ACK;
                else
                    next_state = STATE_DEVICE_ID;
            end

            STATE_ACK: begin
                if (!requested_address_valid) begin
                    next_state = master_valid ? STATE_ACK : STATE_IDLE;
                end
                else if (!requested_slave_ready) begin
                    next_state = STATE_ACK;
                end
                else if (!master_valid) begin
                    // Wait for the low-valid separator before forwarding the
                    // first local-address bit to the selected slave.
                    next_state = STATE_TRANSFER;
                end
                else begin
                    next_state = STATE_ACK;
                end
            end

            STATE_TRANSFER: begin
                if (split_request && (slave_select == SPLIT_SEL))
                    next_state = STATE_IDLE;
                else if (slave_busy_seen && selected_slave_ready)
                    next_state = STATE_IDLE;
                else
                    next_state = STATE_TRANSFER;
            end

            default: next_state = STATE_IDLE;
        endcase
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= STATE_IDLE;
            device_address   <= {DEVICE_ADDR_WIDTH{1'b0}};
            bit_count        <= 8'd0;
            slave_select     <= 2'd0;
            slave_busy_seen  <= 1'b0;
            split_pending    <= 1'b0;
        end
        else begin
            state <= next_state;

            case (state)
                STATE_IDLE: begin
                    bit_count       <= 8'd0;
                    slave_busy_seen <= 1'b0;

                    if (split_resume && split_pending) begin
                        slave_select    <= SPLIT_SEL;
                        split_pending   <= 1'b0;
                        slave_busy_seen <= 1'b1;
                    end
                    else if (master_valid) begin
                        device_address    <= {DEVICE_ADDR_WIDTH{1'b0}};
                        device_address[0] <= serial_data;
                        if (DEVICE_ADDR_WIDTH > 1)
                            bit_count <= 8'd1;
                    end
                end

                STATE_DEVICE_ID: begin
                    if (master_valid) begin
                        device_address[bit_count] <= serial_data;

                        if (bit_count == DEVICE_ADDR_WIDTH-1)
                            bit_count <= 8'd0;
                        else
                            bit_count <= bit_count + 1'b1;
                    end
                end

                STATE_ACK: begin
                    if (requested_address_valid)
                        slave_select <= device_address[1:0];
                end

                STATE_TRANSFER: begin
                    if (!selected_slave_ready)
                        slave_busy_seen <= 1'b1;

                    if (split_request && (slave_select == SPLIT_SEL)) begin
                        split_pending   <= 1'b1;
                        slave_busy_seen <= 1'b0;
                    end
                    else if (slave_busy_seen && selected_slave_ready) begin
                        slave_busy_seen <= 1'b0;
                    end
                end

                default: begin
                    bit_count       <= 8'd0;
                    slave_busy_seen <= 1'b0;
                end
            endcase
        end
    end
endmodule
