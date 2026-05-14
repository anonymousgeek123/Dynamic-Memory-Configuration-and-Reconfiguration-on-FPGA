
// =============================================================================
// region_manager.sv  ?  iverilog-12 compatible
// Manages N region_fifo instances with alloc/free/reconfiguration.
// reconfig_en input: held LOW during init to prevent premature stealing.
// =============================================================================

`timescale 1ns/1ps

module region_manager #(
    parameter integer NUM_REGIONS  = 4,
    parameter integer ADDR_W       = 32,
    parameter integer MAX_DEPTH    = 64,
    parameter integer PTR_W        = 6,
    parameter integer CNT_W        = 7,
    parameter integer RGN_W        = 2,
    parameter integer LOW_THRESH   = 4,
    parameter integer HIGH_THRESH  = 10
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              reconfig_en,   // enable reconfig FSM (tie 0 during init)

    input  wire [NUM_REGIONS-1:0]             alloc_req,
    output reg  [NUM_REGIONS-1:0][ADDR_W-1:0] alloc_addr,
    output reg  [NUM_REGIONS-1:0]             alloc_ack,
    output reg  [NUM_REGIONS-1:0]             alloc_fail,

    input  wire [NUM_REGIONS-1:0]             free_req,
    input  wire [NUM_REGIONS-1:0][ADDR_W-1:0] free_addr,

    output wire [NUM_REGIONS-1:0][CNT_W-1:0]  region_count,
    output wire [NUM_REGIONS-1:0]             region_full,
    output wire [NUM_REGIONS-1:0]             region_empty,

    output reg               reconfig_active,
    output reg  [RGN_W-1:0] reconfig_src,
    output reg  [RGN_W-1:0] reconfig_dst
);

    // -----------------------------------------------------------------------
    // FIFO wires
    // -----------------------------------------------------------------------
    reg  [NUM_REGIONS-1:0]             push_valid_w;
    reg  [NUM_REGIONS-1:0][ADDR_W-1:0] push_addr_w;
    wire [NUM_REGIONS-1:0]             push_ready_w;

    reg  [NUM_REGIONS-1:0]             pop_valid_w;
    wire [NUM_REGIONS-1:0][ADDR_W-1:0] pop_addr_w;
    wire [NUM_REGIONS-1:0]             pop_ready_w;

    reg  [NUM_REGIONS-1:0]             steal_valid_w;
    wire [NUM_REGIONS-1:0][ADDR_W-1:0] steal_addr_w;
    wire [NUM_REGIONS-1:0]             steal_ready_w;

    wire [NUM_REGIONS-1:0][CNT_W-1:0]  count_w;
    wire [NUM_REGIONS-1:0]             full_w, empty_w;

    assign region_count = count_w;
    assign region_full  = full_w;
    assign region_empty = empty_w;

    // -----------------------------------------------------------------------
    // FIFO instantiation
    // -----------------------------------------------------------------------
    genvar g;
    generate
        for (g = 0; g < NUM_REGIONS; g = g + 1) begin : gen_fifo
            region_fifo #(
                .ADDR_W(ADDR_W), .MAX_DEPTH(MAX_DEPTH), .PTR_W(PTR_W), .CNT_W(CNT_W)
            ) u_fifo (
                .clk(clk), .rst_n(rst_n),
                .push_valid(push_valid_w[g]), .push_addr(push_addr_w[g]),
                .push_ready(push_ready_w[g]),
                .pop_valid(pop_valid_w[g]),   .pop_addr(pop_addr_w[g]),
                .pop_ready(pop_ready_w[g]),
                .steal_valid(steal_valid_w[g]), .steal_addr(steal_addr_w[g]),
                .steal_ready(steal_ready_w[g]),
                .count(count_w[g]), .full(full_w[g]), .empty(empty_w[g])
            );
        end
    endgenerate

    // -----------------------------------------------------------------------
    // Reconfig FSM state
    // -----------------------------------------------------------------------
    localparam [1:0] ST_IDLE=2'd0, ST_STEAL=2'd1, ST_DONATE=2'd2;

    reg [1:0]        state;
    reg [RGN_W-1:0]  src_idx, dst_idx;
    reg [ADDR_W-1:0] held_addr;

    // -----------------------------------------------------------------------
    // Combinational: find hungry / rich region indices
    // -----------------------------------------------------------------------
    reg [RGN_W-1:0] hungry_idx, rich_idx;
    reg             has_hungry, has_rich;
    integer         ci;

    always @(*) begin
        hungry_idx = 0; rich_idx = 0;
        has_hungry = 0; has_rich  = 0;
        for (ci = 0; ci < NUM_REGIONS; ci = ci + 1)
            if (count_w[ci] < LOW_THRESH) begin
                has_hungry = 1;
                hungry_idx = ci[RGN_W-1:0];
            end
        for (ci = 0; ci < NUM_REGIONS; ci = ci + 1)
            if (count_w[ci] > HIGH_THRESH && ci[RGN_W-1:0] != hungry_idx) begin
                has_rich = 1;
                rich_idx = ci[RGN_W-1:0];
            end
    end

    // -----------------------------------------------------------------------
    // Combinational: drive FIFO ports
    // -----------------------------------------------------------------------
    integer pi;
    always @(*) begin
        for (pi = 0; pi < NUM_REGIONS; pi = pi + 1) begin
            push_valid_w[pi]  = 0;
            push_addr_w[pi]   = 0;
            pop_valid_w[pi]   = 0;
            steal_valid_w[pi] = 0;
            alloc_addr[pi]    = pop_addr_w[pi];
            alloc_ack[pi]     = 0;
            alloc_fail[pi]    = 0;
        end

        for (pi = 0; pi < NUM_REGIONS; pi = pi + 1) begin
            // free ? push
            if (free_req[pi] && push_ready_w[pi]) begin
                push_valid_w[pi] = 1;
                push_addr_w[pi]  = free_addr[pi];
            end
            // alloc ? pop (suppressed if reconfig stealing from same region)
            if (alloc_req[pi]) begin
                if (state == ST_STEAL && src_idx == pi[RGN_W-1:0]) begin
                    alloc_fail[pi] = 1;
                end else if (pop_ready_w[pi]) begin
                    pop_valid_w[pi] = 1;
                    alloc_ack[pi]   = 1;
                end else begin
                    alloc_fail[pi]  = 1;
                end
            end
        end

        // Reconfig overrides
        case (state)
            ST_STEAL: begin
                steal_valid_w[src_idx] = 1;
                pop_valid_w[src_idx]   = 0;
            end
            ST_DONATE: begin
                push_valid_w[dst_idx] = 1;
                push_addr_w[dst_idx]  = held_addr;
            end
            default: ;
        endcase
    end

    // -----------------------------------------------------------------------
    // FSM sequential
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            src_idx         <= 0;
            dst_idx         <= 0;
            held_addr       <= 0;
            reconfig_active <= 0;
            reconfig_src    <= 0;
            reconfig_dst    <= 0;
        end else begin
            case (state)
                ST_IDLE: begin
                    reconfig_active <= 0;
                    if (reconfig_en && has_hungry && has_rich) begin
                        src_idx         <= rich_idx;
                        dst_idx         <= hungry_idx;
                        reconfig_active <= 1;
                        reconfig_src    <= rich_idx;
                        reconfig_dst    <= hungry_idx;
                        state           <= ST_STEAL;
                    end
                end

                ST_STEAL: begin
                    if (steal_ready_w[src_idx]) begin
                        held_addr <= steal_addr_w[src_idx];
                        state     <= ST_DONATE;
                    end else begin
                        state           <= ST_IDLE;
                        reconfig_active <= 0;
                    end
                end

                ST_DONATE: begin
                    if (push_ready_w[dst_idx]) begin
                        if ((count_w[dst_idx] + 1) < LOW_THRESH &&
                             count_w[src_idx]       > HIGH_THRESH) begin
                            state <= ST_STEAL;
                        end else begin
                            state           <= ST_IDLE;
                            reconfig_active <= 0;
                        end
                    end else begin
                        state           <= ST_IDLE;
                        reconfig_active <= 0;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end
	
endmodule

