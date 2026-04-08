`timescale 1ns/1ps

module parser_tb;
    reg clk;
    reg rst_n;
    reg in_valid;
    reg [7:0] in_data;
    reg in_sop;
    reg in_eop;
    wire hdr_valid;
    wire is_ipv4;
    wire [7:0] protocol;
    wire [31:0] src_ip;
    wire [31:0] dst_ip;
    wire [15:0] src_port;
    wire [15:0] dst_port;
    wire parse_error;

    reg [7:0] udp_mem [0:63];
    reg [7:0] tcp_mem [0:63];
    integer i;

    eth_ipv4_parser dut (
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

    task send_udp_packet;
        begin
            for (i = 0; i < 38; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_data  = udp_mem[i];
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

    task send_tcp_packet;
        begin
            for (i = 0; i < 38; i = i + 1) begin
                @(negedge clk);
                in_valid = 1'b1;
                in_data  = tcp_mem[i];
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
        rst_n    = 1'b0;
        in_valid = 1'b0;
        in_data  = 8'd0;
        in_sop   = 1'b0;
        in_eop   = 1'b0;

        #30;
        rst_n = 1'b1;

        send_udp_packet;
        wait(hdr_valid || parse_error);
        @(negedge clk);
        if (!hdr_valid || !is_ipv4 || protocol != 8'h11 ||
            src_ip != 32'hC0A8010A || dst_ip != 32'hC0A80101 ||
            src_port != 16'h1234 || dst_port != 16'h0050 || parse_error) begin
            $display("FAIL: UDP parse mismatch protocol=%02h src_ip=%08h dst_ip=%08h src_port=%04h dst_port=%04h parse_error=%0d",
                     protocol, src_ip, dst_ip, src_port, dst_port, parse_error);
            $finish;
        end

        repeat (3) @(posedge clk);

        send_tcp_packet;
        wait(hdr_valid || parse_error);
        @(negedge clk);
        if (!hdr_valid || !is_ipv4 || protocol != 8'h06 ||
            src_ip != 32'h0A00002A || dst_ip != 32'hC0A80163 ||
            src_port != 16'h1234 || dst_port != 16'h0017 || parse_error) begin
            $display("FAIL: TCP parse mismatch protocol=%02h src_ip=%08h dst_ip=%08h src_port=%04h dst_port=%04h parse_error=%0d",
                     protocol, src_ip, dst_ip, src_port, dst_port, parse_error);
            $finish;
        end

        $display("PASS: parser_tb");
        $finish;
    end
endmodule
