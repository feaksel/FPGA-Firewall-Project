`timescale 1ns/1ps

module de1_soc_top_bypass_tb;
    import fw_tb_pkg::*;

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
    logic [7:0] udp_mem [0:63];
    int idx;

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

    w5500_macraw_model #(
        .PACKET_FILE(UDP_ALLOW_MEM),
        .PACKET_LENGTH(UDP_ALLOW_LEN),
        .REPEAT_PACKETS(1)
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
        $readmemh(UDP_ALLOW_MEM, udp_mem);
        key = 4'b1110;
        sw = 10'd0;

        #100;
        key[0] = 1'b1;
        sw[0] = 1'b1;
        sw[7] = 1'b1;

        wait(tx_send_count_b == 32'd3);
        repeat (10) @(posedge clk);

        expect_bit("top_bypass.init_done", ledr[0], 1'b1);
        expect_bit("top_bypass.init_error", ledr[1], 1'b0);
        expect_bit("top_bypass.saw_recv_a", saw_recv_cmd_a, 1'b1);
        expect_bit("top_bypass.saw_send_b", saw_send_cmd_b, 1'b1);
        expect_u16("top_bypass.tx_frame_len", tx_frame_len_b, UDP_ALLOW_LEN);
        expect_u32("top_bypass.tx_send_count", tx_send_count_b, 32'd3);

        for (idx = 0; idx < UDP_ALLOW_LEN; idx = idx + 1)
            u_b_model.expect_sent_byte(idx, udp_mem[idx]);

        $display("PASS: de1_soc_top_bypass_tb");
        $finish;
    end
endmodule
