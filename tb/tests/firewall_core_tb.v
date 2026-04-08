`timescale 1ns/1ps

module firewall_core_tb;
    reg clk;
    reg rst_n;
    reg in_valid;
    reg [7:0] in_data;
    reg in_sop;
    reg in_eop;
    reg [0:0] in_src_port;
    wire in_ready;
    wire [31:0] rx_count;
    wire [31:0] allow_count;
    wire [31:0] drop_count;
    wire last_action_allow;
    wire [3:0] last_matched_rule_id;

    reg [7:0] udp_mem [0:63];
    reg [7:0] tcp_mem [0:63];
    integer i;

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

    task send_packet;
        input integer use_udp;
        begin
            for (i = 0; i < 38; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_data  = use_udp ? udp_mem[i] : tcp_mem[i];
                in_sop   = (i == 0);
                in_eop   = (i == 37);
            end
            @(negedge clk);
            in_valid = 1'b0;
            in_sop   = 1'b0;
            in_eop   = 1'b0;
            in_data  = 8'd0;
        end
    endtask

    initial begin
        $readmemh("tb/packets/udp_allow.mem", udp_mem);
        $readmemh("tb/packets/tcp_drop.mem", tcp_mem);
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n       = 1'b0;
        in_valid    = 1'b0;
        in_data     = 8'd0;
        in_sop      = 1'b0;
        in_eop      = 1'b0;
        in_src_port = 1'b0;

        #30;
        rst_n = 1'b1;

        send_packet(1);
        wait(allow_count == 32'd1);
        @(negedge clk);

        send_packet(0);
        wait(drop_count == 32'd1);
        @(negedge clk);

        if (rx_count != 32'd2 || allow_count != 32'd1 || drop_count != 32'd1) begin
            $display("FAIL: counter mismatch rx=%0d allow=%0d drop=%0d",
                     rx_count, allow_count, drop_count);
            $finish;
        end

        if (last_action_allow !== 1'b0 || last_matched_rule_id !== 4'd1) begin
            $display("FAIL: expected last decision drop by rule 1, got allow=%0d rule=%0d",
                     last_action_allow, last_matched_rule_id);
            $finish;
        end

        $display("PASS: firewall_core_tb");
        $finish;
    end
endmodule
