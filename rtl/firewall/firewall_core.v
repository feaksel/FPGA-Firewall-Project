module firewall_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_eop,
    input  wire [0:0]  in_src_port,
    output wire        in_ready,

    output wire [31:0] rx_count,
    output wire [31:0] allow_count,
    output wire [31:0] drop_count,
    output reg         last_action_allow,
    output reg  [3:0]  last_matched_rule_id
);
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

    wire rx_pkt_pulse;
    wire allow_pulse;
    wire drop_pulse;

    assign in_ready     = 1'b1;
    assign rx_pkt_pulse = in_valid && in_sop;
    assign allow_pulse  = decision_valid && action_allow;
    assign drop_pulse   = parse_error || (decision_valid && !action_allow);

    eth_ipv4_parser u_parser (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
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
            last_action_allow    <= 1'b0;
            last_matched_rule_id <= 4'hF;
        end else begin
            if (decision_valid) begin
                last_action_allow    <= action_allow;
                last_matched_rule_id <= matched_rule_id;
            end else if (parse_error) begin
                last_action_allow    <= 1'b0;
                last_matched_rule_id <= 4'hE;
            end
        end
    end
endmodule
