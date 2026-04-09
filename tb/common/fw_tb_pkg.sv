`timescale 1ns/1ps

package fw_tb_pkg;
    localparam int UDP_ALLOW_LEN     = 38;
    localparam int TCP_DROP_LEN      = 38;
    localparam int UDP_SUBNET_LEN    = 38;
    localparam int TCP_ALLOW_SSH_LEN = 38;

    localparam string UDP_ALLOW_MEM     = "tb/packets/udp_allow.mem";
    localparam string TCP_DROP_MEM      = "tb/packets/tcp_drop.mem";
    localparam string UDP_SUBNET_MEM    = "tb/packets/udp_subnet.mem";
    localparam string TCP_ALLOW_SSH_MEM = "tb/packets/tcp_allow_ssh.mem";

    typedef struct packed {
        logic [7:0]  protocol;
        logic [31:0] src_ip;
        logic [31:0] dst_ip;
        logic [15:0] src_port;
        logic [15:0] dst_port;
    } parsed_fields_t;

    function automatic parsed_fields_t parsed_expect_udp_allow();
        parsed_fields_t exp;
        exp.protocol = 8'h11;
        exp.src_ip   = 32'hC0A8010A;
        exp.dst_ip   = 32'hC0A80101;
        exp.src_port = 16'h1234;
        exp.dst_port = 16'h0050;
        return exp;
    endfunction

    function automatic parsed_fields_t parsed_expect_tcp_drop();
        parsed_fields_t exp;
        exp.protocol = 8'h06;
        exp.src_ip   = 32'h0A00002A;
        exp.dst_ip   = 32'hC0A80163;
        exp.src_port = 16'h1234;
        exp.dst_port = 16'h0017;
        return exp;
    endfunction

    function automatic parsed_fields_t parsed_expect_tcp_allow_ssh();
        parsed_fields_t exp;
        exp.protocol = 8'h06;
        exp.src_ip   = 32'h0A010203;
        exp.dst_ip   = 32'hC0A80163;
        exp.src_port = 16'h08AE;
        exp.dst_port = 16'h0016;
        return exp;
    endfunction

    task automatic clear_stream(
        ref logic       valid,
        ref logic [7:0] data,
        ref logic       sop,
        ref logic       eop
    );
        valid = 1'b0;
        data  = 8'd0;
        sop   = 1'b0;
        eop   = 1'b0;
    endtask

    task automatic drive_packet(
        ref    logic        clk,
        input  int          packet_len,
        input  logic [7:0]  pkt_mem [],
        ref    logic        valid,
        ref    logic [7:0]  data,
        ref    logic        sop,
        ref    logic        eop
    );
        int idx;
        for (idx = 0; idx < packet_len; idx++) begin
            @(negedge clk);
            valid = 1'b1;
            data  = pkt_mem[idx];
            sop   = (idx == 0);
            eop   = (idx == (packet_len - 1));
        end

        @(negedge clk);
        clear_stream(valid, data, sop, eop);
    endtask

    task automatic expect_bit(
        input string      label,
        input logic       actual,
        input logic       expected
    );
        if (actual !== expected) begin
            $error("%s mismatch: got %0b expected %0b", label, actual, expected);
            $fatal(1);
        end
    endtask

    task automatic expect_u4(
        input string      label,
        input logic [3:0] actual,
        input logic [3:0] expected
    );
        if (actual !== expected) begin
            $error("%s mismatch: got %0d expected %0d", label, actual, expected);
            $fatal(1);
        end
    endtask

    task automatic expect_u8(
        input string      label,
        input logic [7:0] actual,
        input logic [7:0] expected
    );
        if (actual !== expected) begin
            $error("%s mismatch: got 0x%02h expected 0x%02h", label, actual, expected);
            $fatal(1);
        end
    endtask

    task automatic expect_u16(
        input string       label,
        input logic [15:0] actual,
        input logic [15:0] expected
    );
        if (actual !== expected) begin
            $error("%s mismatch: got 0x%04h expected 0x%04h", label, actual, expected);
            $fatal(1);
        end
    endtask

    task automatic expect_u32(
        input string       label,
        input logic [31:0] actual,
        input logic [31:0] expected
    );
        if (actual !== expected) begin
            $error("%s mismatch: got 0x%08h expected 0x%08h", label, actual, expected);
            $fatal(1);
        end
    endtask

    task automatic expect_parsed_fields(
        input string          prefix,
        input parsed_fields_t actual,
        input parsed_fields_t expected
    );
        expect_u8({prefix, ".protocol"}, actual.protocol, expected.protocol);
        expect_u32({prefix, ".src_ip"}, actual.src_ip, expected.src_ip);
        expect_u32({prefix, ".dst_ip"}, actual.dst_ip, expected.dst_ip);
        expect_u16({prefix, ".src_port"}, actual.src_port, expected.src_port);
        expect_u16({prefix, ".dst_port"}, actual.dst_port, expected.dst_port);
    endtask
endpackage
