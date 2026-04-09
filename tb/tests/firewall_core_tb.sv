`timescale 1ns/1ps

module firewall_core_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic [7:0] in_data;
    logic in_sop;
    logic in_eop;
    logic [0:0] in_src_port;
    logic in_ready;
    logic [31:0] rx_count;
    logic [31:0] allow_count;
    logic [31:0] drop_count;
    logic last_action_allow;
    logic [3:0] last_matched_rule_id;

    logic [7:0] udp_mem [0:63];
    logic [7:0] tcp_drop_mem [0:63];
    logic [7:0] tcp_allow_ssh_mem [0:63];

    firewall_core dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_src_port(in_src_port),
        .in_ready(in_ready),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id)
    );

    initial begin
        $readmemh(UDP_ALLOW_MEM, udp_mem);
        $readmemh(TCP_DROP_MEM, tcp_drop_mem);
        $readmemh(TCP_ALLOW_SSH_MEM, tcp_allow_ssh_mem);
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n       = 1'b0;
        in_src_port = '0;
        clear_stream(in_valid, in_data, in_sop, in_eop);

        #30;
        rst_n = 1'b1;

        drive_packet(clk, UDP_ALLOW_LEN, udp_mem, in_valid, in_data, in_sop, in_eop);
        wait(allow_count == 32'd1);
        @(negedge clk);
        expect_u32("after_udp.rx_count", rx_count, 32'd1);
        expect_u32("after_udp.allow_count", allow_count, 32'd1);
        expect_u32("after_udp.drop_count", drop_count, 32'd0);
        expect_bit("after_udp.last_action_allow", last_action_allow, 1'b1);
        expect_u4("after_udp.last_matched_rule_id", last_matched_rule_id, 4'd0);

        drive_packet(clk, TCP_ALLOW_SSH_LEN, tcp_allow_ssh_mem, in_valid, in_data, in_sop, in_eop);
        wait(allow_count == 32'd2);
        @(negedge clk);
        expect_u32("after_ssh.rx_count", rx_count, 32'd2);
        expect_u32("after_ssh.allow_count", allow_count, 32'd2);
        expect_u32("after_ssh.drop_count", drop_count, 32'd0);
        expect_bit("after_ssh.last_action_allow", last_action_allow, 1'b1);
        expect_u4("after_ssh.last_matched_rule_id", last_matched_rule_id, 4'd2);

        drive_packet(clk, TCP_DROP_LEN, tcp_drop_mem, in_valid, in_data, in_sop, in_eop);
        wait(drop_count == 32'd1);
        @(negedge clk);
        expect_u32("final.rx_count", rx_count, 32'd3);
        expect_u32("final.allow_count", allow_count, 32'd2);
        expect_u32("final.drop_count", drop_count, 32'd1);
        expect_bit("final.last_action_allow", last_action_allow, 1'b0);
        expect_u4("final.last_matched_rule_id", last_matched_rule_id, 4'd1);

        $display("PASS: firewall_core_tb");
        $finish;
    end
endmodule
