`timescale 1ns/1ps

module firewall_forwarder_tb;
    import fw_tb_pkg::*;

    localparam int FWD_FRAME_LEN = 42;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic [7:0] in_data;
    logic in_sop;
    logic in_eop;
    logic [0:0] in_src_port;
    logic in_ready;
    logic out_valid;
    logic [7:0] out_data;
    logic out_sop;
    logic out_eop;
    logic [0:0] out_src_port;
    logic out_ready;
    logic [31:0] rx_count;
    logic [31:0] allow_count;
    logic [31:0] drop_count;
    logic [31:0] rule_allow80_count;
    logic [31:0] rule_allow5001_count;
    logic [31:0] rule_drop5002_count;
    logic [31:0] rule_content_block_count;
    logic [31:0] rule_default_drop_count;
    logic [31:0] sig_file_count;
    logic [31:0] sig_sine_count;
    logic last_action_allow;
    logic [3:0] last_matched_rule_id;
    logic buffer_overflow;

    logic [7:0] udp_mem [0:63];
    logic [7:0] udp_5001_mem [0:63];
    logic [7:0] udp_5002_mem [0:63];
    logic [7:0] udp_block_mem [0:79];
    logic [7:0] tcp_drop_mem [0:63];
    int out_count;
    int drop_wait;

    firewall_forwarder #(
        .MAX_PKT_BYTES(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_src_port(in_src_port),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_sop(out_sop),
        .out_eop(out_eop),
        .out_src_port(out_src_port),
        .out_ready(out_ready),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .rule_allow80_count(rule_allow80_count),
        .rule_allow5001_count(rule_allow5001_count),
        .rule_drop5002_count(rule_drop5002_count),
        .rule_content_block_count(rule_content_block_count),
        .rule_default_drop_count(rule_default_drop_count),
        .sig_file_count(sig_file_count),
        .sig_sine_count(sig_sine_count),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id),
        .buffer_overflow(buffer_overflow)
    );

    initial begin
        $readmemh(UDP_ALLOW_MEM, udp_mem);
        $readmemh(TCP_DROP_MEM, tcp_drop_mem);
        for (int idx = 0; idx < 64; idx++) begin
            if (idx >= UDP_ALLOW_LEN)
                udp_mem[idx] = 8'h00;
            if (idx >= TCP_DROP_LEN)
                tcp_drop_mem[idx] = 8'h00;
            udp_5001_mem[idx] = udp_mem[idx];
            udp_5002_mem[idx] = udp_mem[idx];
        end
        udp_5001_mem[36] = 8'h13;
        udp_5001_mem[37] = 8'h89;
        udp_5002_mem[36] = 8'h13;
        udp_5002_mem[37] = 8'h8A;

        for (int idx = 0; idx < 80; idx++)
            udp_block_mem[idx] = 8'h00;
        for (int idx = 0; idx < UDP_ALLOW_LEN; idx++)
            udp_block_mem[idx] = udp_mem[idx];
        udp_block_mem[38] = 8'h00;
        udp_block_mem[39] = 8'h10;
        udp_block_mem[40] = 8'h00;
        udp_block_mem[41] = 8'h00;
        udp_block_mem[42] = "F";
        udp_block_mem[43] = "W";
        udp_block_mem[44] = "-";
        udp_block_mem[45] = "B";
        udp_block_mem[46] = "L";
        udp_block_mem[47] = "O";
        udp_block_mem[48] = "C";
        udp_block_mem[49] = "K";
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            if ((out_count < FWD_FRAME_LEN) && (out_data !== udp_mem[out_count])) begin
                $error("forwarded byte %0d mismatch: got 0x%02h expected 0x%02h",
                       out_count, out_data, udp_mem[out_count]);
                $fatal(1);
            end
            if ((out_count < FWD_FRAME_LEN) && (out_sop !== (out_count == 0))) begin
                $error("forwarded sop mismatch at byte %0d", out_count);
                $fatal(1);
            end
            if ((out_count < FWD_FRAME_LEN) && (out_eop !== (out_count == (FWD_FRAME_LEN - 1)))) begin
                $error("forwarded eop mismatch at byte %0d", out_count);
                $fatal(1);
            end
            out_count++;
        end
    end

    initial begin
        rst_n       = 1'b0;
        in_src_port = '0;
        out_ready   = 1'b1;
        out_count   = 0;
        clear_stream(in_valid, in_data, in_sop, in_eop);

        #30;
        rst_n = 1'b1;

        drive_packet(clk, FWD_FRAME_LEN, udp_mem, in_valid, in_data, in_sop, in_eop);
        drop_wait = 0;
        while ((out_count != FWD_FRAME_LEN) && (drop_wait < 200)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (out_count != FWD_FRAME_LEN) begin
            $error("timeout waiting for forwarded UDP packet: out_count=%0d rx=%0d allow=%0d drop=%0d in_ready=%0b out_valid=%0b",
                   out_count, rx_count, allow_count, drop_count, in_ready, out_valid);
            $fatal(1);
        end
        @(negedge clk);
        expect_u32("forwarder.after_allow.rx_count", rx_count, 32'd1);
        expect_u32("forwarder.after_allow.allow_count", allow_count, 32'd1);
        expect_u32("forwarder.after_allow.drop_count", drop_count, 32'd0);
        expect_u32("forwarder.after_allow.rule_allow80", rule_allow80_count, 32'd1);
        expect_bit("forwarder.after_allow.last_action", last_action_allow, 1'b1);
        expect_u4("forwarder.after_allow.rule", last_matched_rule_id, 4'd0);
        expect_bit("forwarder.after_allow.overflow", buffer_overflow, 1'b0);

        drive_packet(clk, FWD_FRAME_LEN, udp_5001_mem, in_valid, in_data, in_sop, in_eop);
        drop_wait = 0;
        while ((allow_count != 32'd2) && (drop_wait < 300)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (allow_count != 32'd2) begin
            $error("timeout waiting for UDP/5001 allow: rx=%0d allow=%0d drop=%0d rule=%0h out=%0d",
                   rx_count, allow_count, drop_count, last_matched_rule_id, out_count);
            $fatal(1);
        end
        repeat (20) @(negedge clk);
        expect_u32("forwarder.after_5001.allow_count", allow_count, 32'd2);
        expect_u32("forwarder.after_5001.rule_allow5001", rule_allow5001_count, 32'd1);
        expect_u4("forwarder.after_5001.rule", last_matched_rule_id, 4'd3);
        drop_wait = 0;
        while ((out_count != (FWD_FRAME_LEN * 2)) && (drop_wait < 300)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (out_count != (FWD_FRAME_LEN * 2)) begin
            $error("timeout waiting for second forwarded packet to drain: out=%0d", out_count);
            $fatal(1);
        end

        drive_packet(clk, FWD_FRAME_LEN, udp_5002_mem, in_valid, in_data, in_sop, in_eop);
        drop_wait = 0;
        while ((drop_count != 32'd1) && (drop_wait < 300)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (drop_count != 32'd1) begin
            $error("timeout waiting for UDP/5002 drop: rx=%0d allow=%0d drop=%0d rule=%0h out=%0d",
                   rx_count, allow_count, drop_count, last_matched_rule_id, out_count);
            $fatal(1);
        end
        repeat (20) @(negedge clk);
        expect_u32("forwarder.after_5002.drop_count", drop_count, 32'd1);
        expect_u32("forwarder.after_5002.rule_drop5002", rule_drop5002_count, 32'd1);
        expect_u4("forwarder.after_5002.rule", last_matched_rule_id, 4'd4);

        drive_packet(clk, 50, udp_block_mem, in_valid, in_data, in_sop, in_eop);
        drop_wait = 0;
        while ((drop_count != 32'd2) && (drop_wait < 300)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (drop_count != 32'd2) begin
            $error("timeout waiting for content drop: rx=%0d allow=%0d drop=%0d rule=%0h out=%0d",
                   rx_count, allow_count, drop_count, last_matched_rule_id, out_count);
            $fatal(1);
        end
        repeat (20) @(negedge clk);
        expect_u32("forwarder.after_block.rule_content_block", rule_content_block_count, 32'd1);
        expect_u4("forwarder.after_block.rule", last_matched_rule_id, 4'd5);

        drive_packet(clk, FWD_FRAME_LEN, tcp_drop_mem, in_valid, in_data, in_sop, in_eop);
        drop_wait = 0;
        while ((drop_count != 32'd3) && (drop_wait < 300)) begin
            @(negedge clk);
            drop_wait++;
        end
        if (drop_count != 32'd3) begin
            $error("timeout waiting for TCP/23 drop: rx=%0d allow=%0d drop=%0d rule=%0h out=%0d",
                   rx_count, allow_count, drop_count, last_matched_rule_id, out_count);
            $fatal(1);
        end
        drop_wait = 0;
        repeat (30) begin
            @(negedge clk);
            if (out_valid)
                drop_wait++;
        end
        expect_u32("forwarder.final.rx_count", rx_count, 32'd5);
        expect_u32("forwarder.final.allow_count", allow_count, 32'd2);
        expect_u32("forwarder.final.drop_count", drop_count, 32'd3);
        expect_u32("forwarder.final.out_count", out_count, FWD_FRAME_LEN * 2);
        expect_u4("forwarder.final.rule", last_matched_rule_id, 4'd1);
        expect_u32("forwarder.final.default_drop", rule_default_drop_count, 32'd0);
        expect_u32("forwarder.drop_wait", drop_wait, 32'd0);

        $display("PASS: firewall_forwarder_tb");
        $finish;
    end
endmodule
