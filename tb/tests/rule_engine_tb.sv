`timescale 1ns/1ps

module rule_engine_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic hdr_valid;
    logic [7:0] protocol;
    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic decision_valid;
    logic action_allow;
    logic [3:0] matched_rule_id;

    rule_engine dut (
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

    task automatic drive_header(
        input logic [7:0]  t_protocol,
        input logic [31:0] t_src_ip,
        input logic [31:0] t_dst_ip,
        input logic [15:0] t_src_port,
        input logic [15:0] t_dst_port
    );
        @(negedge clk);
        protocol  = t_protocol;
        src_ip    = t_src_ip;
        dst_ip    = t_dst_ip;
        src_port  = t_src_port;
        dst_port  = t_dst_port;
        hdr_valid = 1'b1;

        @(negedge clk);
        hdr_valid = 1'b0;
    endtask

    task automatic expect_decision(
        input string      label,
        input logic       expected_allow,
        input logic [3:0] expected_rule
    );
        wait(decision_valid);
        @(negedge clk);
        expect_bit({label, ".decision_valid"}, decision_valid, 1'b1);
        expect_bit({label, ".action_allow"}, action_allow, expected_allow);
        expect_u4({label, ".matched_rule_id"}, matched_rule_id, expected_rule);
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n      = 1'b0;
        hdr_valid  = 1'b0;
        protocol   = 8'd0;
        src_ip     = 32'd0;
        dst_ip     = 32'd0;
        src_port   = 16'd0;
        dst_port   = 16'd0;

        #20;
        rst_n = 1'b1;

        drive_header(8'h11, 32'hC0A80155, 32'hC0A80101, 16'd1234, 16'd80);
        expect_decision("rule0_udp_allow", 1'b1, 4'd0);

        drive_header(8'h06, 32'h0A000001, 32'hC0A80163, 16'd1234, 16'd23);
        expect_decision("rule1_tcp_drop", 1'b0, 4'd1);

        drive_header(8'h06, 32'h0A010203, 32'hC0A80163, 16'd2222, 16'd22);
        expect_decision("rule2_ssh_allow", 1'b1, 4'd2);

        drive_header(8'h11, 32'hAC100001, 32'h08080808, 16'd9999, 16'd53);
        expect_decision("rule3_udp_default_allow", 1'b1, 4'd3);

        drive_header(8'h06, 32'hAC100001, 32'h08080808, 16'd9999, 16'd443);
        expect_decision("default_drop", 1'b0, 4'hF);

        $display("PASS: rule_engine_tb");
        $finish;
    end
endmodule
