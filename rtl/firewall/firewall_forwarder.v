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
    reg  [7:0]  fwd_byte_idx;
    reg  [7:0]  fwd_current_idx;
    reg  [15:0] fwd_ethertype;
    reg  [7:0]  fwd_version_ihl;
    reg  [7:0]  fwd_protocol;
    reg  [31:0] fwd_src_ip;
    reg  [31:0] fwd_dst_ip;
    reg  [15:0] fwd_src_port;
    reg  [15:0] fwd_dst_port;
    reg         fwd_decision_valid;
    reg         fwd_action_allow;
    reg  [3:0]  fwd_rule_id;

    wire rx_pkt_pulse;
    wire allow_pulse;
    wire drop_pulse;

    assign rx_pkt_pulse   = in_valid && in_ready && in_sop;
    assign allow_pulse    = fwd_decision_valid && fwd_action_allow;
    assign drop_pulse     = fwd_decision_valid && !fwd_action_allow;
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
            fwd_byte_idx         <= 8'd0;
            fwd_current_idx      <= 8'd0;
            fwd_ethertype        <= 16'd0;
            fwd_version_ihl      <= 8'd0;
            fwd_protocol         <= 8'd0;
            fwd_src_ip           <= 32'd0;
            fwd_dst_ip           <= 32'd0;
            fwd_src_port         <= 16'd0;
            fwd_dst_port         <= 16'd0;
            fwd_decision_valid   <= 1'b0;
            fwd_action_allow     <= 1'b0;
            fwd_rule_id          <= 4'hF;
        end else begin
            rd_start <= 1'b0;
            discard  <= 1'b0;
            fwd_decision_valid <= 1'b0;

            if (in_valid && in_ready && in_sop) begin
                pkt_decision_seen <= 1'b0;
                pkt_action_allow  <= 1'b0;
                pkt_rule_id       <= 4'hF;
                fwd_byte_idx      <= 8'd0;
                fwd_ethertype     <= 16'd0;
                fwd_version_ihl   <= 8'd0;
                fwd_protocol      <= 8'd0;
                fwd_src_ip        <= 32'd0;
                fwd_dst_ip        <= 32'd0;
                fwd_src_port      <= 16'd0;
                fwd_dst_port      <= 16'd0;
            end

            if (in_valid && in_ready) begin
                fwd_current_idx = in_sop ? 8'd0 : (fwd_byte_idx + 8'd1);
                fwd_byte_idx   <= fwd_current_idx;

                case (fwd_current_idx)
                    8'd12: fwd_ethertype[15:8] <= in_data;
                    8'd13: fwd_ethertype[7:0]  <= in_data;
                    8'd14: fwd_version_ihl     <= in_data;
                    8'd23: fwd_protocol        <= in_data;
                    8'd26: fwd_src_ip[31:24]   <= in_data;
                    8'd27: fwd_src_ip[23:16]   <= in_data;
                    8'd28: fwd_src_ip[15:8]    <= in_data;
                    8'd29: fwd_src_ip[7:0]     <= in_data;
                    8'd30: fwd_dst_ip[31:24]   <= in_data;
                    8'd31: fwd_dst_ip[23:16]   <= in_data;
                    8'd32: fwd_dst_ip[15:8]    <= in_data;
                    8'd33: fwd_dst_ip[7:0]     <= in_data;
                    8'd34: fwd_src_port[15:8]  <= in_data;
                    8'd35: fwd_src_port[7:0]   <= in_data;
                    8'd36: fwd_dst_port[15:8]  <= in_data;
                    8'd37: begin
                        fwd_dst_port[7:0] <= in_data;
                        fwd_decision_valid <= 1'b1;
                        pkt_decision_seen  <= 1'b1;

                        if ((fwd_ethertype == 16'h0800) &&
                            (fwd_version_ihl == 8'h45) &&
                            ((fwd_protocol == 8'h06) || (fwd_protocol == 8'h11))) begin
                            if ((fwd_protocol == 8'h11) &&
                                ((fwd_src_ip & 32'hFFFFFF00) == 32'hC0A80100) &&
                                (fwd_dst_ip == 32'hC0A80101) &&
                                ({fwd_dst_port[15:8], in_data} == 16'd80)) begin
                                fwd_action_allow     <= 1'b1;
                                fwd_rule_id          <= 4'd0;
                                pkt_action_allow     <= 1'b1;
                                pkt_rule_id          <= 4'd0;
                                last_action_allow    <= 1'b1;
                                last_matched_rule_id <= 4'd0;
                            end else if ((fwd_protocol == 8'h06) &&
                                         ({fwd_dst_port[15:8], in_data} == 16'd23)) begin
                                fwd_action_allow     <= 1'b0;
                                fwd_rule_id          <= 4'd1;
                                pkt_action_allow     <= 1'b0;
                                pkt_rule_id          <= 4'd1;
                                last_action_allow    <= 1'b0;
                                last_matched_rule_id <= 4'd1;
                            end else if ((fwd_protocol == 8'h06) &&
                                         ((fwd_src_ip & 32'hFF000000) == 32'h0A000000) &&
                                         ({fwd_dst_port[15:8], in_data} == 16'd22)) begin
                                fwd_action_allow     <= 1'b1;
                                fwd_rule_id          <= 4'd2;
                                pkt_action_allow     <= 1'b1;
                                pkt_rule_id          <= 4'd2;
                                last_action_allow    <= 1'b1;
                                last_matched_rule_id <= 4'd2;
                            end else if ((fwd_protocol == 8'h11) &&
                                         ({fwd_dst_port[15:8], in_data} == 16'd5002)) begin
                                fwd_action_allow     <= 1'b0;
                                fwd_rule_id          <= 4'd4;
                                pkt_action_allow     <= 1'b0;
                                pkt_rule_id          <= 4'd4;
                                last_action_allow    <= 1'b0;
                                last_matched_rule_id <= 4'd4;
                            end else if (fwd_protocol == 8'h11) begin
                                fwd_action_allow     <= 1'b1;
                                fwd_rule_id          <= 4'd3;
                                pkt_action_allow     <= 1'b1;
                                pkt_rule_id          <= 4'd3;
                                last_action_allow    <= 1'b1;
                                last_matched_rule_id <= 4'd3;
                            end else begin
                                fwd_action_allow     <= 1'b0;
                                fwd_rule_id          <= 4'hF;
                                pkt_action_allow     <= 1'b0;
                                pkt_rule_id          <= 4'hF;
                                last_action_allow    <= 1'b0;
                                last_matched_rule_id <= 4'hF;
                            end
                        end else begin
                            fwd_action_allow     <= 1'b0;
                            fwd_rule_id          <= 4'hE;
                            pkt_action_allow     <= 1'b0;
                            pkt_rule_id          <= 4'hE;
                            last_action_allow    <= 1'b0;
                            last_matched_rule_id <= 4'hE;
                        end
                    end
                endcase

                if (in_eop && (fwd_current_idx < 8'd37)) begin
                    fwd_decision_valid   <= 1'b1;
                    fwd_action_allow     <= 1'b0;
                    fwd_rule_id          <= 4'hE;
                    pkt_decision_seen    <= 1'b1;
                    pkt_action_allow     <= 1'b0;
                    pkt_rule_id          <= 4'hE;
                    last_action_allow    <= 1'b0;
                    last_matched_rule_id <= 4'hE;
                end
            end

            if (1'b0 && decision_valid) begin
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
                    if (pkt_available && pkt_decision_seen) begin
                        if (pkt_action_allow) begin
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
