# Drop-in 4-Slave Bus Bridge Update for `Dulina14/sys-bus`

This package is designed against the current `main` branch structure of:

`https://github.com/Dulina14/sys-bus`

It leaves the working three-slave `integrated_system_bus.v` build untouched and adds a separate bridge build.

## Bridge architecture

- Master 1: normal local master
- Master 2: UART bus-bridge master
- Slave 1: 2 KB memory
- Slave 2: 4 KB memory
- Slave 3: 4 KB split-capable memory
- Slave 4: UART bus-bridge slave

## 16-bit address format

```text
[15:14]  local slave ID
          00 = S1
          01 = S2
          10 = S3
          11 = S4 bridge

[13:12]  remote slave ID (used only when local ID is 11)

[11:0]   memory address
```

Examples:

```text
00 | 00 | 0x350  -> local Slave 1, address 0x350
01 | 00 | 0x350  -> local Slave 2, address 0x350
10 | 00 | 0x350  -> local Slave 3, address 0x350
11 | 00 | 0x350  -> remote Slave 1, address 0x350
11 | 01 | 0x350  -> remote Slave 2, address 0x350
11 | 10 | 0x350  -> remote Slave 3, address 0x350
11 | 11 | 0x350  -> RESERVED to prevent bridge-to-bridge loops
```

## Copy locations

Copy the files in this package into the same relative paths in your repository.

### `member2/rtl/`

- `bus_mux4.v`
- `bus_slave_valid_decoder4.v`
- `bus_arbiter_4slave.v`
- `serial_address_decoder_4slave.v`
- `serial_bus_m2_s4.v`

### `integrated/rtl/`

- `bridge_addr_convert.v`
- `bridge_uart_tx.v`
- `bridge_uart_rx.v`
- `bridge_uart.v`
- `serial_bus_bridge_slave.v`
- `serial_bus_bridge_master.v`
- `integrated_system_bus_bridge.v`

### `integrated/board/`

- `de0_nano_bridge_top.v`

### `integrated/tb/`

- `tb_bridge_loop.sv`

### `integrated/scripts/`

- `run_bridge_simulation.ps1`

## Existing files reused unchanged

The bridge build reuses these files already in your repo:

- `member2/rtl/bus_mux2.v`
- `integrated/rtl/serial_master_port.v`
- `integrated/rtl/serial_slave_port.v`
- `integrated/rtl/serial_slave_memory.v`
- `integrated/rtl/serial_bus_slave.v`

Do not replace the normal three-slave files unless you intentionally want to remove the old build.

## UART physical connection between two identical boards

Each board contains TWO bridge UART endpoints: one for its bridge master and one for its bridge slave. Cross-connect them as follows:

```text
Board A bridge_slave_uart_tx  -> Board B bridge_master_uart_rx
Board A bridge_slave_uart_rx  <- Board B bridge_master_uart_tx

Board A bridge_master_uart_tx -> Board B bridge_slave_uart_rx
Board A bridge_master_uart_rx <- Board B bridge_slave_uart_tx

Board A GND                    <-> Board B GND
```

The default hardware baud setting uses `UART_CLOCKS_PER_BIT=5208` for a 50 MHz clock, approximately 9600 baud.

## UART frame format

Request from bridge slave to remote bridge master:

```text
1 bit mode + 8 bits data + 14 bits bridge address = 23 data bits
```

- mode 0 = read
- mode 1 = write
- read request data field is zero

Read response from bridge master to remote bridge slave:

```text
8 data bits
```

UART framing is one start bit, LSB-first data bits, one stop bit, no parity.

## Important limitation

Remote target ID `2'b11` is reserved. Do not try to target the other board's Slave 4 bridge, because that would create a bridge-to-bridge forwarding loop.

The current arbiter remains conservative: it expects all non-split resources to become ready before starting new work. For evaluation, perform bridge transactions one at a time rather than initiating simultaneous cross-board transactions from both boards.

## Simulation

From the repository root:

```powershell
& .\integrated\scripts\run_bridge_simulation.ps1
```

The testbench instantiates two complete bridge-enabled systems, cross-connects their UARTs, and checks remote writes and reads in both directions.

## Quartus

Create a separate bridge Quartus project/QSF rather than overwriting the working normal project. Use `integrated/quartus_bridge_additions.txt` as the source-file list. You still need to choose four unused GPIO pins for the four UART signals and connect the two board grounds.
