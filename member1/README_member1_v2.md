# Member 1 — Master Port (v2, aligned to the reference project)

Files: `rtl/master_port.v`, `rtl/demo_master.v`, `tb/tb_master_port.v`

This supersedes the earlier draft. It's now built directly off the
**ADS_Bus_Project_Report.docx** you shared (Pasqual & Rathnayake, EN4021),
so it should drop straight into an arbiter / address-decoder / slave that
follow the same report — with one deliberate change (async reset) to meet
our own assignment's requirement.

## 1. What I copied from the reference, and why

The reference project's `master_port` is a clean, working design, so I
kept its **interface, state names, LSB-first serial framing, and split
handling exactly as written** — that's what makes this compatible with an
arbiter/address-decoder/slave built the same way. Specifically:

- **One combined address bus** (`daddr[ADDR_WIDTH-1:0]`), not a separate
  slave-ID field. The **top** `ADDR_WIDTH-SLAVE_MEM_ADDR_WIDTH` bits select
  the slave; the low `SLAVE_MEM_ADDR_WIDTH` bits are the local address
  inside that slave. With the default parameters (`ADDR_WIDTH=16`,
  `SLAVE_MEM_ADDR_WIDTH=12`) that's a **4-bit slave-select + 12-bit local
  address** — which also matches our own earlier project note ("send a
  four-bit slave ID, then a twelve-bit local address"), just expressed as
  the top 4 bits of one address bus instead of a separate wire.
- **LSB-first serial shifting**, using a plain bit-indexed counter
  (`addr[counter]`, `wdata[counter]`) rather than a shift register — this
  is what the reference's `slave_port`/`addr_decoder` also expect, so all
  three modules count the same way in lock-step.
- **Ready/valid local handshake**: `dvalid`/`dready`/`dmode`/`daddr`/
  `dwdata`/`drdata`, instead of a bespoke `req_i`/`busy_o`/`done_o` set.
- **Split handling lives almost entirely in the arbiter.** The master does
  **not** have a "parked" output. It just keeps `mbreq` asserted the whole
  time (even while in `SPLIT`) and reacts to two inputs: `msplit` (this
  read has split) and `mbgrant` (arbiter has re-granted the bus). Once
  `!msplit && mbgrant`, it goes straight back into `RDATA` — no address
  resend. This matches the reference's arbiter, which tracks
  `split_owner`/`msplit1`/`msplit2` itself and is responsible for letting
  the *other* master use the bus while this one is parked.
- **WAIT-state ack timeout**: if the address decoder never pulses `ack`
  within `TIMEOUT_TIME` cycles, the transaction is abandoned back to
  `IDLE` (invalid address / addressed slave not present).

## 2. What I changed, and why

**Asynchronous reset.** The reference's `master_port` only resets
synchronously:
```verilog
always @(posedge clk) begin
    state <= (!rstn) ? IDLE : next_state;
end
```
Our assignment explicitly requires **async reset with posedge clocks**, so
every register here lives in `always @(posedge clk or negedge rstn)`
instead. This is the only functional difference from the reference's
`master_port` — everything else (state encodings, bit ordering, timeout,
split behaviour) is unchanged, so it stays compatible with the rest of the
team using the same reference for the arbiter/slave/address-decoder.
**If Member 2 and Member 3 also switch to async reset for consistency**,
they'll need the same one-line change: add `or negedge rstn` to every
`always @(posedge clk)` and initialise every register in an `if (!rstn)`
branch — happy to help with that once you share their draft files.

I also fixed one ambiguity in the reference report's WAIT-state next-state
expression (the extracted text was garbled by the Word→PDF conversion in
a couple of spots); the actual logic, confirmed from the rendered PDF, is:
`ack ? ADDR : (timeout==TIMEOUT_TIME ? IDLE : WAIT)` — i.e. time out to
`IDLE`, not `ADDR`. That's what's implemented here.

Everything else (bus-bridge / UART, the specific arbiter/address-decoder/
slave RTL) is **out of scope** for our assignment (2 masters, 3 slaves, no
bridge) and was not carried over.

## 3. IO Definition — `master_port`

Parameters: `ADDR_WIDTH=16`, `DATA_WIDTH=8`, `SLAVE_MEM_ADDR_WIDTH=12`,
`TIMEOUT_TIME=5` (→ `SLAVE_DEVICE_ADDR_WIDTH = ADDR_WIDTH-SLAVE_MEM_ADDR_WIDTH = 4`).

Local (parallel) side:

| Port | Dir | Width | Description |
|---|---|---|---|
| clk, rstn | in | 1 | clock, **async active-low** reset |
| daddr | in | 16 | address (top 4 bits = slave select, low 12 = local addr) |
| dwdata | in | 8 | write data |
| dmode | in | 1 | 0 = read, 1 = write |
| dvalid | in | 1 | daddr/dwdata/dmode valid; starts a transaction |
| drdata | out | 8 | data from a read transaction |
| dready | out | 1 | master idle, ready for the next request |

Serial bus side (Member 2's arbiter / mux / addr_decoder):

| Port | Dir | Width | Description |
|---|---|---|---|
| mwdata | out | 1 | serial data out (slave-select / local addr / write data) |
| mvalid | out | 1 | mwdata valid this cycle |
| mmode | out | 1 | 0 = read, 1 = write |
| mrdata | in | 1 | serial data in (read data from slave) |
| svalid | in | 1 | mrdata valid this cycle |
| mbreq | out | 1 | request the shared bus |
| mbgrant | in | 1 | arbiter grants the bus |
| msplit | in | 1 | addressed slave has split this read |
| ack | in | 1 | address decoder acknowledges a valid slave address |

## 4. State machine

```
IDLE -> REQ -> SADDR -> WAIT -> ADDR -+-> WDATA -> IDLE                       (write)
                                      +-> RDATA -> IDLE                       (read, no split)
                                      +-> RDATA -> SPLIT -> RDATA -> IDLE     (read, split)
        (WAIT can also time out -> IDLE if ack never comes)
```

## 5. How to simulate

```bash
iverilog -g2012 -o sim_master tb/tb_master_port.v rtl/master_port.v
vvp sim_master
gtkwave tb_master_port.vcd     # for report screenshots
```

Reference run: **26/26 checks PASSED** — reset test, single write, single
read, delayed-grant wait, WAIT-timeout abort, and split interruption/resume
(with `mbreq` verified to stay asserted throughout `SPLIT`, per the
reference's design).

## 6. `demo_master.v` (DE0 board demo)

Same idea as before, updated to the new port names: `KEY[0]`=reset,
`KEY[1]`=fire one transaction, `SW[9]`=`dmode`, `SW[8:5]`=slave-select
nibble, `SW[4:0]`=local address bits, results on `LEDR`. `DEMO_MODE="AUTO"`
still gives a free-running variant usable as Master 2 in a live two-master
demo.

## 7. Next step

Send over Member 2's `arbiter`/`addr_decoder`/`bus_m2_s3` and Member 3's
`slave_port` drafts (or point me at which parts of the reference report
they're using as-is vs. changing) and I'll check the exact handshake
timing against this `master_port` — in particular: how many cycles after
`mvalid` falls does `ack` arrive, whether `msplit` is guaranteed to be
stable by the first `RDATA` cycle, and whether they're keeping the
reference's synchronous reset or switching to async to match this module.
