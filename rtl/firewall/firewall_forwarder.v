`timescale 1ns/1ps

module firewall_forwarder #(
    parameter MAX_PKT_BYTES = 2048
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_eop,
    input  wire [0:0]  in_src_port,
    output wire        in_ready,

    output wire        out_valid,
    output wire [7:0]  out_data,
    output wire        out_sop,
    output wire        out_eop,
    output wire [0:0]  out_src_port,
    input  wire        out_ready,

    output wire [31:0] rx_count,
    output wire [31:0] allow_count,
    output wire [31:0] drop_count,
    output reg         last_action_allow,
    output reg  [3:0]  last_matched_rule_id,
    output wire        buffer_overflow
);
    localparam ST_WAIT_PACKET = 2'd0;
    localparam ST_FORWARD     = 2'd1;
    localparam ST_DROP        = 2'd2;

    wire        hdr_valid;
    wire        is_ipv4;
    wire [7:0]  protocol;
    wire [31:0] src_ip;
    wire [31:0] dst_ip;
    wire [15:0] src_port;
    wire [15:0] dst_port;
    wire        parse_error;

    wire        decision_valid;
    wire        action_allow;
    wire [3:0]  matched_rule_id;

    wire        pkt_done;
    wire        pkt_available;
    wire [15:0] pkt_len;
    wire        pktbuf_overflow;
    reg         pkt_decision_seen;
    reg         pkt_action_allow;
    reg  [3:0]  pkt_rule_id;
    reg  [1:0]  state;
    reg         rd_start;
    reg         discard;

    wire rx_pkt_pulse;
    wire allow_pulse;
    wire drop_pulse;

    assign rx_pkt_pulse   = in_valid && in_ready && in_sop;
    assign allow_pulse    = decision_valid && action_allow;
    assign drop_pulse     = parse_error || (decision_valid && !action_allow);
    assign buffer_overflow = pktbuf_overflow;

    packet_buffer #(
        .MAX_PKT_BYTES(MAX_PKT_BYTES)
    ) u_packet_buffer (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_src_port(in_src_port),
        .in_ready(in_ready),
        .rd_start(rd_start),
        .discard(discard),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_sop(out_sop),
        .out_eop(out_eop),
        .out_src_port(out_src_port),
        .out_ready(out_ready),
        .pkt_len(pkt_len),
        .pkt_done(pkt_done),
        .pkt_available(pkt_available),
        .overflow_error(pktbuf_overflow)
    );

    eth_ipv4_parser u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid && in_ready),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .hdr_valid(hdr_valid),
        .is_ipv4(is_ipv4),
        .protocol(protocol),
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .parse_error(parse_error)
    );

    rule_engine u_rules (
        .clk(clk),
        .rst_n(rst_n),
        .hdr_valid(hdr_valid),
        .protocol(protocol),
        .src_ip(src_ip),
        .dst_ip(dst_ip),
        .src_port(src_port),
        .dst_port(dst_port),
        .decision_valid(decision_valid),
        .action_allow(action_allow),
        .matched_rule_id(matched_rule_id)
    );

    debug_counters u_debug_counters (
        .clk(clk),
        .rst_n(rst_n),
        .rx_pkt_pulse(rx_pkt_pulse),
        .allow_pulse(allow_pulse),
        .drop_pulse(drop_pulse),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= ST_WAIT_PACKET;
            rd_start             <= 1'b0;
            discard              <= 1'b0;
            pkt_decision_seen    <= 1'b0;
            pkt_action_allow     <= 1'b0;
            pkt_rule_id          <= 4'hF;
            last_action_allow    <= 1'b0;
            last_matched_rule_id <= 4'hF;
        end else begin
            rd_start <= 1'b0;
            discard  <= 1'b0;

            if (in_valid && in_ready && in_sop) begin
                pkt_decision_seen <= 1'b0;
                pkt_action_allow  <= 1'b0;
                pkt_rule_id       <= 4'hF;
            end

            if (decision_valid) begin
                pkt_decision_seen    <= 1'b1;
                pkt_action_allow     <= action_allow;
                pkt_rule_id          <= matched_rule_id;
                last_action_allow    <= action_allow;
                last_matched_rule_id <= matched_rule_id;
            end else if (parse_error) begin
                pkt_decision_seen    <= 1'b1;
                pkt_action_allow     <= 1'b0;
                pkt_rule_id          <= 4'hE;
                last_action_allow    <= 1'b0;
                last_matched_rule_id <= 4'hE;
            end

            case (state)
                ST_WAIT_PACKET: begin
                    if (pkt_available) begin
                        if (pkt_decision_seen && pkt_action_allow) begin
                            rd_start <= 1'b1;
                            state    <= ST_FORWARD;
                        end else begin
                            discard <= 1'b1;
                            state   <= ST_DROP;
                        end
                    end
                end

                ST_FORWARD: begin
                    if (!pkt_available && !out_valid)
                        state <= ST_WAIT_PACKET;
                end

                ST_DROP: begin
                    state <= ST_WAIT_PACKET;
                end

                default: begin
                    state <= ST_WAIT_PACKET;
                end
            endcase
        end
    end
endmodule
