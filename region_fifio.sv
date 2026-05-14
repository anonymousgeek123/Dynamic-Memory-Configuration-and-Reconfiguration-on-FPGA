// =============================================================================
// region_fifo.sv  ?  iverilog-12 compatible
// Circular FIFO of free DDR page addresses for one memory region.
// =============================================================================

`timescale 1ns/1ps

module region_fifo #(
    parameter integer ADDR_W    = 32,
    parameter integer MAX_DEPTH = 64,   // power-of-2
    parameter integer PTR_W     = 6,    // $clog2(MAX_DEPTH)
    parameter integer CNT_W     = 7     // $clog2(MAX_DEPTH+1)
)(
    input  wire              clk,
    input  wire              rst_n,

    input  wire              push_valid,
    input  wire [ADDR_W-1:0] push_addr,
    output reg               push_ready,

    input  wire              pop_valid,
    output reg  [ADDR_W-1:0] pop_addr,
    output reg               pop_ready,

    input  wire              steal_valid,
    output reg  [ADDR_W-1:0] steal_addr,
    output reg               steal_ready,

    output reg  [CNT_W-1:0]  count,
    output reg               full,
    output reg               empty
);

    reg [ADDR_W-1:0] mem [0:MAX_DEPTH-1];
    reg [PTR_W-1:0]  wr_ptr;
    reg [PTR_W-1:0]  rd_ptr;
    reg [CNT_W-1:0]  cnt;
    integer          idx;

    wire is_full  = (cnt == MAX_DEPTH);
    wire is_empty = (cnt == 0);

    wire do_push  = push_valid  & ~is_full;
    wire do_pop   = pop_valid   & ~is_empty & ~(steal_valid & ~is_empty);
    wire do_steal = steal_valid & ~is_empty & ~(pop_valid   & ~is_empty);

    always @(*) begin
        full        = is_full;
        empty       = is_empty;
        push_ready  = ~is_full;
        pop_ready   = ~is_empty;
        steal_ready = ~is_empty;
        pop_addr    = mem[rd_ptr];
        steal_addr  = mem[rd_ptr];
        count       = cnt;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            cnt    <= 0;
            for (idx = 0; idx < MAX_DEPTH; idx = idx + 1)
                mem[idx] <= 0;
        end else begin
            if (do_push) begin
                mem[wr_ptr] <= push_addr;
                wr_ptr      <= wr_ptr + 1;
            end
            if (do_pop || do_steal)
                rd_ptr <= rd_ptr + 1;
            case ({do_push, do_pop | do_steal})
                2'b10:   cnt <= cnt + 1;
                2'b01:   cnt <= cnt - 1;
                default: cnt <= cnt;
            endcase
        end
    end

endmodule
