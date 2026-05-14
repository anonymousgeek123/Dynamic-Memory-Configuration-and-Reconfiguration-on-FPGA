module top_wrapper (
    input  wire clk,
    input  wire [3:0] KEY,
    output wire [3:0] led,
    output wire [6:0] HEX0   // 7-seg display
);

    // Reset (KEY2)
    wire rst_n = KEY[2];

    // Edge detection
    reg [3:0] key_prev;
    wire [3:0] key_press;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            key_prev <= 4'b1111;
        else
            key_prev <= KEY;
    end

    assign key_press = key_prev & ~KEY;

    // Alloc requests
    wire [3:0] alloc_req;
    assign alloc_req[0] = key_press[0];
    assign alloc_req[1] = key_press[1];
    assign alloc_req[2] = key_press[3];
    assign alloc_req[3] = 1'b0;

    wire [3:0] free_req = 4'b0000;
    wire [3:0][31:0] free_addr = '0;

    wire [3:0][31:0] alloc_addr;
    wire [3:0] alloc_ack, alloc_fail;
    wire [3:0][6:0] region_count;
    wire [3:0] region_full, region_empty;
    wire init_done, reconfig_active;
    wire [1:0] reconfig_src, reconfig_dst;

    ddr_mem_allocator u_ddr (
        .clk(clk),
        .rst_n(rst_n),
        .alloc_req(alloc_req),
        .alloc_addr(alloc_addr),
        .alloc_ack(alloc_ack),
        .alloc_fail(alloc_fail),
        .free_req(free_req),
        .free_addr(free_addr),
        .region_count(region_count),
        .region_full(region_full),
        .region_empty(region_empty),
        .init_done(init_done),
        .reconfig_active(reconfig_active),
        .reconfig_src(reconfig_src),
        .reconfig_dst(reconfig_dst)
    );

    // LEDs (same as before)
    reg [3:0] led_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            led_reg <= 4'b0000;
        else begin
            led_reg[0] <= init_done;
            led_reg[1] <= reconfig_active;

            if (|alloc_ack)
                led_reg[2] <= 1;

            if (|alloc_fail)
                led_reg[3] <= 1;
        end
    end

    assign led = led_reg;

    // --------------------------------------------------
    // 7-SEG DISPLAY (region_count[0])
    // --------------------------------------------------
    wire [3:0] display_val;
    assign display_val = region_count[0][3:0];  // show lower 4 bits

    seven_seg_decoder u_seg (
        .bin(display_val),
        .seg(HEX0)
    );

endmodule