// =============================================================================
// ddr_mem_allocator.sv  ?  iverilog-12 compatible
// Top-level: INIT FSM populates region FIFOs, then hands off to region_manager.
// Reconfig is disabled during init to prevent premature page stealing.
// =============================================================================

`timescale 1ns/1ps

module ddr_mem_allocator #(
    parameter integer NUM_REGIONS           = 4,
    parameter integer ADDR_W                = 32,
    parameter integer MAX_DEPTH             = 16,
    parameter integer PTR_W                 = 4,   // $clog2(MAX_DEPTH)
    parameter integer CNT_W                 = 5,   // $clog2(MAX_DEPTH+1)
    parameter integer RGN_W                 = 2,   // $clog2(NUM_REGIONS)
    parameter integer IPGW                  = 5,   // $clog2(INIT_PAGES_PER_REGION+1)
    parameter integer INIT_PAGES_PER_REGION = 8,
    parameter integer PAGE_SIZE             = 4096,
    parameter [31:0]  BASE_ADDR             = 32'h0000_0000,
    parameter integer LOW_THRESH            = 4,
    parameter integer HIGH_THRESH           = 10
)(
    input  wire              clk,
    input  wire              rst_n,

    input  wire [NUM_REGIONS-1:0]             alloc_req,
    output wire [NUM_REGIONS-1:0][ADDR_W-1:0] alloc_addr,
    output wire [NUM_REGIONS-1:0]             alloc_ack,
    output wire [NUM_REGIONS-1:0]             alloc_fail,

    input  wire [NUM_REGIONS-1:0]             free_req,
    input  wire [NUM_REGIONS-1:0][ADDR_W-1:0] free_addr,

    output wire [NUM_REGIONS-1:0][CNT_W-1:0]  region_count,
    output wire [NUM_REGIONS-1:0]             region_full,
    output wire [NUM_REGIONS-1:0]             region_empty,
    output reg               init_done,
    output wire              reconfig_active,
    output wire [RGN_W-1:0] reconfig_src,
    output wire [RGN_W-1:0] reconfig_dst
);

    // -----------------------------------------------------------------------
    // INIT FSM states
    // -----------------------------------------------------------------------
    localparam [1:0] S_FILL=2'd0, S_WAIT=2'd1, S_RUN=2'd2;

    reg [1:0]       top_state;
    reg [RGN_W-1:0] init_region;
    reg [IPGW-1:0]  init_page;

    reg [NUM_REGIONS-1:0]             init_free_req;
    reg [NUM_REGIONS-1:0][ADDR_W-1:0] init_free_addr;

    // reconfig_en: only allow reconfig after init finishes
    wire reconfig_en = (top_state == S_RUN);

    // Mux inputs to manager
    wire [NUM_REGIONS-1:0]             mgr_alloc_req = reconfig_en ? alloc_req  : 0;
    wire [NUM_REGIONS-1:0]             mgr_free_req  = reconfig_en ? free_req   : init_free_req;
    wire [NUM_REGIONS-1:0][ADDR_W-1:0] mgr_free_addr = reconfig_en ? free_addr  : init_free_addr;

    integer ri;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_state   <= S_FILL;
            init_region <= 0;
            init_page   <= 0;
            init_done   <= 0;
            for (ri = 0; ri < NUM_REGIONS; ri = ri + 1) begin
                init_free_req[ri]  <= 0;
                init_free_addr[ri] <= 0;
            end
        end else begin
            for (ri = 0; ri < NUM_REGIONS; ri = ri + 1)
                init_free_req[ri] <= 0;

            case (top_state)
                S_FILL: begin
                    // Push page address for current region
                    init_free_req[init_region]  <= 1;
                    init_free_addr[init_region] <=
                        BASE_ADDR +
                        (init_region * INIT_PAGES_PER_REGION + init_page) * PAGE_SIZE;
                    top_state <= S_WAIT;
                end

                S_WAIT: begin
                    if (init_page == INIT_PAGES_PER_REGION - 1) begin
                        init_page <= 0;
                        if (init_region == NUM_REGIONS - 1) begin
                            top_state <= S_RUN;
                            init_done <= 1;
                        end else begin
                            init_region <= init_region + 1;
                            top_state   <= S_FILL;
                        end
                    end else begin
                        init_page <= init_page + 1;
                        top_state <= S_FILL;
                    end
                end

                S_RUN: init_done <= 1;

                default: top_state <= S_RUN;
            endcase
        end
    end

    // -----------------------------------------------------------------------
    // region_manager instance
    // -----------------------------------------------------------------------
    region_manager #(
        .NUM_REGIONS (NUM_REGIONS),
        .ADDR_W      (ADDR_W),
        .MAX_DEPTH   (MAX_DEPTH),
        .PTR_W       (PTR_W),
        .CNT_W       (CNT_W),
        .RGN_W       (RGN_W),
        .LOW_THRESH  (LOW_THRESH),
        .HIGH_THRESH (HIGH_THRESH)
    ) u_mgr (
        .clk            (clk),
        .rst_n          (rst_n),
        .reconfig_en    (reconfig_en),
        .alloc_req      (mgr_alloc_req),
        .alloc_addr     (alloc_addr),
        .alloc_ack      (alloc_ack),
        .alloc_fail     (alloc_fail),
        .free_req       (mgr_free_req),
        .free_addr      (mgr_free_addr),
        .region_count   (region_count),
        .region_full    (region_full),
        .region_empty   (region_empty),
        .reconfig_active(reconfig_active),
        .reconfig_src   (reconfig_src),
        .reconfig_dst   (reconfig_dst)
    );

endmodule
