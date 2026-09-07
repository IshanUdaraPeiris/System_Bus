`timescale 1ns/1ps

// Converts the 14-bit bridge address into the destination bus's 16-bit address.
// Incoming bridge address:
//   [13:12] = destination slave on the remote bus
//   [11:0]  = destination memory address
// Output local address on destination bus:
//   [15:14] = destination slave
//   [13:12] = 2'b00 (no further bridge routing)
//   [11:0]  = memory address
module bridge_addr_convert #(
    parameter BRIDGE_ADDR_WIDTH = 14,
    parameter BUS_ADDR_WIDTH = 16
) (
    input  wire [BRIDGE_ADDR_WIDTH-1:0] bridge_address,
    output wire [BUS_ADDR_WIDTH-1:0]    bus_address
);
    assign bus_address = {
        bridge_address[13:12],
        2'b00,
        bridge_address[11:0]
    };
endmodule
