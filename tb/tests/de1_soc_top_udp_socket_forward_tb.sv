`timescale 1ns/1ps

module de1_soc_top_udp_socket_forward_tb;
    import fw_tb_pkg::*;

    localparam int PAYLOAD_LEN = 306;
    localparam int EXPECTED_FRAME_LEN = 42 + PAYLOAD_LEN;

    logic clk;
    logic [3:0] key;
    logic [9:0] sw;
    wire [9:0] ledr;
    wire [6:0] hex0;
    wire [6:0] hex1;
    wire [6:0] hex2;
    wire [6:0] hex3;
    wire [35:0] gpio_0;
    wire [5:0] gpio_1;

    logic saw_version_read_a;
    logic saw_open_cmd_a;
    logic saw_recv_cmd_a;
    logic saw_send_cmd_b;
    logic [15:0] tx_frame_len_b;
    logic [31:0] tx_send_count_b;

    de1_soc_w5500_top dut (
        .CLOCK_50(clk),
        .KEY(key),
        .SW(sw),
        .LEDR(ledr),
        .HEX0(hex0),
        .HEX1(hex1),
        .HEX2(hex2),
        .HEX3(hex3),
        .GPIO_0(gpio_0),
        .GPIO_1(gpio_1)
    );

    w5500_udp_rx_model #(
        .PACKET_FILE(UDP_ALLOW_MEM),
        .PACKET_LENGTH(UDP_ALLOW_LEN),
        .PAYLOAD_LENGTH(PAYLOAD_LEN),
        .PACKET_SOCKET(1)
    ) u_a_model (
        .rst_n(key[0]),
        .w5500_reset_n(gpio_0[3]),
        .sclk(gpio_0[0]),
        .mosi(gpio_0[1]),
        .miso(gpio_0[4]),
        .cs_n(gpio_0[2]),
        .int_n(gpio_0[5]),
        .saw_version_read(saw_version_read_a),
        .saw_open_cmd(saw_open_cmd_a),
        .saw_recv_cmd(saw_recv_cmd_a)
    );

    w5500_tx_model #(
        .TXBUF_BYTES(2048)
    ) u_b_model (
        .rst_n(key[0]),
        .sclk(gpio_1[0]),
        .mosi(gpio_1[1]),
        .miso(gpio_1[4]),
        .cs_n(gpio_1[2]),
        .saw_send_cmd(saw_send_cmd_b),
        .tx_frame_len(tx_frame_len_b),
        .tx_send_count(tx_send_count_b)
    );

    assign gpio_1[5] = 1'b1;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        key = 4'b1110;
        sw = 10'd0;

        #100;
        key[0] = 1'b1;
        sw[0] = 1'b1;

        wait(tx_send_count_b == 32'd1);
        repeat (10) @(posedge clk);

        expect_bit("top_udp_forward.init_done", ledr[0], 1'b1);
        expect_bit("top_udp_forward.init_error", ledr[1], 1'b0);
        expect_bit("top_udp_forward.saw_recv_a", saw_recv_cmd_a, 1'b1);
        expect_bit("top_udp_forward.saw_send_b", saw_send_cmd_b, 1'b1);
        expect_u16("top_udp_forward.tx_frame_len", tx_frame_len_b, EXPECTED_FRAME_LEN);
        expect_u32("top_udp_forward.tx_send_count", tx_send_count_b, 32'd1);

        u_b_model.expect_sent_byte(0, 8'hff);
        u_b_model.expect_sent_byte(12, 8'h08);
        u_b_model.expect_sent_byte(23, 8'h11);
        u_b_model.expect_sent_byte(26, 8'hc0);
        u_b_model.expect_sent_byte(29, 8'h0a);
        u_b_model.expect_sent_byte(30, 8'hc0);
        u_b_model.expect_sent_byte(33, 8'h01);
        u_b_model.expect_sent_byte(34, 8'h12);
        u_b_model.expect_sent_byte(37, 8'h89);
        u_b_model.expect_sent_byte(42, 8'ha5);
        u_b_model.expect_sent_byte(43, 8'ha4);

        $display("PASS: de1_soc_top_udp_socket_forward_tb");
        $finish;
    end
endmodule
