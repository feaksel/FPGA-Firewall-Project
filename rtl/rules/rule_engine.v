`include "defs.vh"

module rule_engine (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        hdr_valid,
    input  wire [7:0]  protocol,
    input  wire [31:0] src_ip,
    input  wire [31:0] dst_ip,
    input  wire [15:0] src_port,
    input  wire [15:0] dst_port,

    output reg         decision_valid,
    output reg         action_allow,
    output reg  [3:0]  matched_rule_id
);
    parameter RULE0_VALID        = 1;
    parameter RULE0_SRC_IP       = 32'hC0A80100;
    parameter RULE0_SRC_MASK     = 32'hFFFFFF00;
    parameter RULE0_DST_IP       = 32'hC0A80101;
    parameter RULE0_DST_MASK     = 32'hFFFFFFFF;
    parameter RULE0_PROTOCOL     = `PROTO_UDP;
    parameter RULE0_SRC_PORT_MIN = 16'd0;
    parameter RULE0_SRC_PORT_MAX = 16'd65535;
    parameter RULE0_DST_PORT_MIN = 16'd80;
    parameter RULE0_DST_PORT_MAX = 16'd80;
    parameter RULE0_ACTION       = `ACTION_ALLOW;

    parameter RULE1_VALID        = 1;
    parameter RULE1_SRC_IP       = 32'h00000000;
    parameter RULE1_SRC_MASK     = 32'h00000000;
    parameter RULE1_DST_IP       = 32'h00000000;
    parameter RULE1_DST_MASK     = 32'h00000000;
    parameter RULE1_PROTOCOL     = `PROTO_TCP;
    parameter RULE1_SRC_PORT_MIN = 16'd0;
    parameter RULE1_SRC_PORT_MAX = 16'd65535;
    parameter RULE1_DST_PORT_MIN = 16'd23;
    parameter RULE1_DST_PORT_MAX = 16'd23;
    parameter RULE1_ACTION       = `ACTION_DROP;

    parameter RULE2_VALID        = 1;
    parameter RULE2_SRC_IP       = 32'h0A000000;
    parameter RULE2_SRC_MASK     = 32'hFF000000;
    parameter RULE2_DST_IP       = 32'h00000000;
    parameter RULE2_DST_MASK     = 32'h00000000;
    parameter RULE2_PROTOCOL     = `PROTO_TCP;
    parameter RULE2_SRC_PORT_MIN = 16'd0;
    parameter RULE2_SRC_PORT_MAX = 16'd65535;
    parameter RULE2_DST_PORT_MIN = 16'd22;
    parameter RULE2_DST_PORT_MAX = 16'd22;
    parameter RULE2_ACTION       = `ACTION_ALLOW;

    parameter RULE3_VALID        = 1;
    parameter RULE3_SRC_IP       = 32'h00000000;
    parameter RULE3_SRC_MASK     = 32'h00000000;
    parameter RULE3_DST_IP       = 32'h00000000;
    parameter RULE3_DST_MASK     = 32'h00000000;
    parameter RULE3_PROTOCOL     = `PROTO_UDP;
    parameter RULE3_SRC_PORT_MIN = 16'd0;
    parameter RULE3_SRC_PORT_MAX = 16'd65535;
    parameter RULE3_DST_PORT_MIN = 16'd0;
    parameter RULE3_DST_PORT_MAX = 16'd65535;
    parameter RULE3_ACTION       = `ACTION_ALLOW;

    wire rule0_hit;
    wire rule1_hit;
    wire rule2_hit;
    wire rule3_hit;

    assign rule0_hit =
        RULE0_VALID &&
        ((src_ip & RULE0_SRC_MASK) == (RULE0_SRC_IP & RULE0_SRC_MASK)) &&
        ((dst_ip & RULE0_DST_MASK) == (RULE0_DST_IP & RULE0_DST_MASK)) &&
        ((RULE0_PROTOCOL == 8'h00) || (protocol == RULE0_PROTOCOL)) &&
        (src_port >= RULE0_SRC_PORT_MIN) &&
        (src_port <= RULE0_SRC_PORT_MAX) &&
        (dst_port >= RULE0_DST_PORT_MIN) &&
        (dst_port <= RULE0_DST_PORT_MAX);

    assign rule1_hit =
        RULE1_VALID &&
        ((src_ip & RULE1_SRC_MASK) == (RULE1_SRC_IP & RULE1_SRC_MASK)) &&
        ((dst_ip & RULE1_DST_MASK) == (RULE1_DST_IP & RULE1_DST_MASK)) &&
        ((RULE1_PROTOCOL == 8'h00) || (protocol == RULE1_PROTOCOL)) &&
        (src_port >= RULE1_SRC_PORT_MIN) &&
        (src_port <= RULE1_SRC_PORT_MAX) &&
        (dst_port >= RULE1_DST_PORT_MIN) &&
        (dst_port <= RULE1_DST_PORT_MAX);

    assign rule2_hit =
        RULE2_VALID &&
        ((src_ip & RULE2_SRC_MASK) == (RULE2_SRC_IP & RULE2_SRC_MASK)) &&
        ((dst_ip & RULE2_DST_MASK) == (RULE2_DST_IP & RULE2_DST_MASK)) &&
        ((RULE2_PROTOCOL == 8'h00) || (protocol == RULE2_PROTOCOL)) &&
        (src_port >= RULE2_SRC_PORT_MIN) &&
        (src_port <= RULE2_SRC_PORT_MAX) &&
        (dst_port >= RULE2_DST_PORT_MIN) &&
        (dst_port <= RULE2_DST_PORT_MAX);

    assign rule3_hit =
        RULE3_VALID &&
        ((src_ip & RULE3_SRC_MASK) == (RULE3_SRC_IP & RULE3_SRC_MASK)) &&
        ((dst_ip & RULE3_DST_MASK) == (RULE3_DST_IP & RULE3_DST_MASK)) &&
        ((RULE3_PROTOCOL == 8'h00) || (protocol == RULE3_PROTOCOL)) &&
        (src_port >= RULE3_SRC_PORT_MIN) &&
        (src_port <= RULE3_SRC_PORT_MAX) &&
        (dst_port >= RULE3_DST_PORT_MIN) &&
        (dst_port <= RULE3_DST_PORT_MAX);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            decision_valid  <= 1'b0;
            action_allow    <= `ACTION_DROP;
            matched_rule_id <= 4'hF;
        end else begin
            decision_valid <= 1'b0;
            if (hdr_valid) begin
                decision_valid <= 1'b1;

                if (rule0_hit) begin
                    action_allow    <= RULE0_ACTION;
                    matched_rule_id <= 4'd0;
                end else if (rule1_hit) begin
                    action_allow    <= RULE1_ACTION;
                    matched_rule_id <= 4'd1;
                end else if (rule2_hit) begin
                    action_allow    <= RULE2_ACTION;
                    matched_rule_id <= 4'd2;
                end else if (rule3_hit) begin
                    action_allow    <= RULE3_ACTION;
                    matched_rule_id <= 4'd3;
                end else begin
                    action_allow    <= `ACTION_DROP;
                    matched_rule_id <= 4'hF;
                end
            end
        end
    end
endmodule
