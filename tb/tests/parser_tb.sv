`timescale 1ns/1ps

module parser_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic [7:0] in_data;
    logic in_sop;
    logic in_eop;
    logic hdr_valid;
    logic is_ipv4;
    logic [7:0] protocol;
    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic [15:0] src_port;
    logic [15:0] dst_port;
    logic parse_error;
    logic saw_hdr_valid;
    logic saw_parse_error;

    logic [7:0] udp_mem [0:63];
    logic [7:0] tcp_mem [0:63];
    parsed_fields_t captured_fields;

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

    initial begin
        $readmemh(UDP_ALLOW_MEM, udp_mem);
        $readmemh(TCP_DROP_MEM, tcp_mem);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            saw_hdr_valid   <= 1'b0;
            saw_parse_error <= 1'b0;
            captured_fields <= '0;
        end else begin
            if (hdr_valid) begin
                saw_hdr_valid             <= 1'b1;
                captured_fields.protocol  <= protocol;
                captured_fields.src_ip    <= src_ip;
                captured_fields.dst_ip    <= dst_ip;
                captured_fields.src_port  <= src_port;
                captured_fields.dst_port  <= dst_port;
            end

            if (parse_error)
                saw_parse_error <= 1'b1;
        end
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n = 1'b0;
        clear_stream(in_valid, in_data, in_sop, in_eop);

        #30;
        rst_n = 1'b1;

        saw_hdr_valid   = 1'b0;
        saw_parse_error = 1'b0;
        drive_packet(clk, UDP_ALLOW_LEN, udp_mem, in_valid, in_data, in_sop, in_eop);
        wait(saw_hdr_valid || saw_parse_error);
        @(negedge clk);
        expect_bit("udp.hdr_valid", saw_hdr_valid, 1'b1);
        expect_bit("udp.is_ipv4", is_ipv4, 1'b1);
        expect_bit("udp.parse_error", saw_parse_error, 1'b0);
        expect_parsed_fields("udp", captured_fields, parsed_expect_udp_allow());

        repeat (3) @(posedge clk);

        saw_hdr_valid   = 1'b0;
        saw_parse_error = 1'b0;
        drive_packet(clk, TCP_DROP_LEN, tcp_mem, in_valid, in_data, in_sop, in_eop);
        wait(saw_hdr_valid || saw_parse_error);
        @(negedge clk);
        expect_bit("tcp.hdr_valid", saw_hdr_valid, 1'b1);
        expect_bit("tcp.is_ipv4", is_ipv4, 1'b1);
        expect_bit("tcp.parse_error", saw_parse_error, 1'b0);
        expect_parsed_fields("tcp", captured_fields, parsed_expect_tcp_drop());

        $display("PASS: parser_tb");
        $finish;
    end
endmodule
