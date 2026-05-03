`timescale 1ns/1ps

module two_port_bypass_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic start_init;

    logic a_reset_n;
    logic a_int_n;
    logic a_sclk;
    logic a_mosi;
    logic a_miso;
    logic a_cs_n;

    logic b_reset_n;
    logic b_int_n;
    logic b_sclk;
    logic b_mosi;
    logic b_miso;
    logic b_cs_n;

    logic a_init_done;
    logic a_init_error;
    logic a_rx_seen;
    logic a_frame_valid;
    logic [7:0] a_frame_data;
    logic a_frame_sop;
    logic a_frame_eop;
    logic [0:0] a_frame_src_port;
    logic a_frame_ready;

    logic fifo_out_valid;
    logic [7:0] fifo_out_data;
    logic fifo_out_sop;
    logic fifo_out_eop;
    logic [0:0] fifo_out_src_port;
    logic fifo_overflow;

    logic b_init_done;
    logic b_init_error;
    logic b_frame_ready;
    logic [31:0] b_tx_count;
    logic b_tx_error;

    logic saw_version_read;
    logic saw_open_cmd;
    logic saw_recv_cmd;
    logic saw_send_cmd;
    logic [15:0] tx_frame_len;
    logic [31:0] tx_send_count;

    logic [7:0] udp_mem [0:63];
    int idx;

    ethernet_controller_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .RESET_ASSERT_CYCLES(4),
        .RESET_RELEASE_CYCLES(4),
        .RX_POLL_WAIT_CYCLES(2),
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(64)
    ) u_a_rx (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(a_reset_n),
        .w5500_int_n(a_int_n),
        .spi_sclk(a_sclk),
        .spi_mosi(a_mosi),
        .spi_miso(a_miso),
        .spi_cs_n(a_cs_n),
        .init_busy(),
        .init_done(a_init_done),
        .init_error(a_init_error),
        .rx_packet_seen(a_rx_seen),
        .frame_valid(a_frame_valid),
        .frame_data(a_frame_data),
        .frame_sop(a_frame_sop),
        .frame_eop(a_frame_eop),
        .frame_src_port(a_frame_src_port),
        .frame_ready(a_frame_ready),
        .rx_commit_count(),
        .rx_stream_byte_count(),
        .last_rx_size_bytes(),
        .last_frame_len_bytes(),
        .debug_state()
    );

    frame_rx_fifo #(
        .PACKET_DEPTH(4),
        .MAX_PKT_BYTES(64)
    ) u_fifo (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(a_frame_valid),
        .in_data(a_frame_data),
        .in_sop(a_frame_sop),
        .in_eop(a_frame_eop),
        .in_src_port(a_frame_src_port),
        .in_ready(a_frame_ready),
        .out_valid(fifo_out_valid),
        .out_data(fifo_out_data),
        .out_sop(fifo_out_sop),
        .out_eop(fifo_out_eop),
        .out_src_port(fifo_out_src_port),
        .out_ready(b_frame_ready),
        .overflow_error(fifo_overflow)
    );

    w5500_macraw_tx_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .RESET_ASSERT_CYCLES(4),
        .RESET_RELEASE_CYCLES(4),
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(64)
    ) u_b_tx (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(b_reset_n),
        .w5500_int_n(b_int_n),
        .spi_sclk(b_sclk),
        .spi_mosi(b_mosi),
        .spi_miso(b_miso),
        .spi_cs_n(b_cs_n),
        .frame_valid(fifo_out_valid),
        .frame_data(fifo_out_data),
        .frame_sop(fifo_out_sop),
        .frame_eop(fifo_out_eop),
        .frame_ready(b_frame_ready),
        .init_busy(),
        .init_done(b_init_done),
        .init_error(b_init_error),
        .tx_count(b_tx_count),
        .tx_error(b_tx_error),
        .debug_state()
    );

    w5500_macraw_model #(
        .PACKET_FILE(UDP_ALLOW_MEM),
        .PACKET_LENGTH(UDP_ALLOW_LEN),
        .REPEAT_PACKETS(1)
    ) u_a_model (
        .rst_n(rst_n),
        .w5500_reset_n(a_reset_n),
        .sclk(a_sclk),
        .mosi(a_mosi),
        .miso(a_miso),
        .cs_n(a_cs_n),
        .int_n(a_int_n),
        .saw_version_read(saw_version_read),
        .saw_open_cmd(saw_open_cmd),
        .saw_recv_cmd(saw_recv_cmd)
    );

    w5500_tx_model #(
        .TXBUF_BYTES(2048)
    ) u_b_model (
        .rst_n(rst_n),
        .sclk(b_sclk),
        .mosi(b_mosi),
        .miso(b_miso),
        .cs_n(b_cs_n),
        .saw_send_cmd(saw_send_cmd),
        .tx_frame_len(tx_frame_len),
        .tx_send_count(tx_send_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        $readmemh(UDP_ALLOW_MEM, udp_mem);
        b_int_n = 1'b1;
        rst_n = 1'b0;
        start_init = 1'b0;

        #30;
        rst_n = 1'b1;
        @(posedge clk);
        start_init = 1'b1;

        wait(tx_send_count == 32'd3);
        wait(b_tx_count == 32'd3);
        @(negedge clk);

        expect_bit("bypass.a_init_error", a_init_error, 1'b0);
        expect_bit("bypass.b_init_error", b_init_error, 1'b0);
        expect_bit("bypass.fifo_overflow", fifo_overflow, 1'b0);
        expect_bit("bypass.saw_send_cmd", saw_send_cmd, 1'b1);
        expect_u16("bypass.tx_frame_len", tx_frame_len, UDP_ALLOW_LEN);
        expect_u32("bypass.b_tx_count", b_tx_count, 32'd3);

        for (idx = 0; idx < UDP_ALLOW_LEN; idx = idx + 1)
            u_b_model.expect_sent_byte(idx, udp_mem[idx]);

        $display("PASS: two_port_bypass_tb");
        $finish;
    end
endmodule
