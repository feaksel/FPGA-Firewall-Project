`timescale 1ns/1ps

module eth_controller_adapter_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic start_init;
    logic w5500_reset_n;
    logic w5500_int_n;
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;
    logic init_busy;
    logic init_done;
    logic init_error;
    logic rx_packet_seen;
    logic frame_valid;
    logic [7:0] frame_data;
    logic frame_sop;
    logic frame_eop;
    logic [0:0] frame_src_port;
    logic frame_ready;
    logic [3:0] debug_state;
    logic saw_version_read;
    logic saw_open_cmd;
    logic saw_recv_cmd;
    logic [7:0] udp_mem [0:63];
    integer frame_count;

    ethernet_controller_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .RESET_ASSERT_CYCLES(4),
        .RESET_RELEASE_CYCLES(4),
        .RX_POLL_WAIT_CYCLES(2),
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(w5500_reset_n),
        .w5500_int_n(w5500_int_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .init_busy(init_busy),
        .init_done(init_done),
        .init_error(init_error),
        .rx_packet_seen(rx_packet_seen),
        .frame_valid(frame_valid),
        .frame_data(frame_data),
        .frame_sop(frame_sop),
        .frame_eop(frame_eop),
        .frame_src_port(frame_src_port),
        .frame_ready(frame_ready),
        .rx_commit_count(),
        .rx_stream_byte_count(),
        .last_rx_size_bytes(),
        .last_frame_len_bytes(),
        .debug_state(debug_state)
    );

    w5500_macraw_model #(
        .PACKET_FILE(UDP_ALLOW_MEM),
        .PACKET_LENGTH(UDP_ALLOW_LEN)
    ) u_w5500_model (
        .rst_n(rst_n),
        .w5500_reset_n(w5500_reset_n),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .cs_n(spi_cs_n),
        .int_n(w5500_int_n),
        .saw_version_read(saw_version_read),
        .saw_open_cmd(saw_open_cmd),
        .saw_recv_cmd(saw_recv_cmd)
    );

    initial begin
        $readmemh(UDP_ALLOW_MEM, udp_mem);
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (frame_valid && frame_ready) begin
            if (frame_data !== udp_mem[frame_count]) begin
                $error("adapter frame byte mismatch idx=%0d got=0x%02h expected=0x%02h",
                       frame_count, frame_data, udp_mem[frame_count]);
                $fatal(1);
            end
            frame_count = frame_count + 1;
        end
    end

    initial begin
        rst_n      = 1'b0;
        start_init = 1'b0;
        frame_ready = 1'b1;
        frame_count = 0;

        #30;
        rst_n = 1'b1;

        @(posedge clk);
        start_init = 1'b1;
        @(posedge clk);
        start_init = 1'b0;

        wait(init_done);
        wait(rx_packet_seen);
        @(negedge clk);

        expect_bit("adapter.init_error", init_error, 1'b0);
        expect_bit("adapter.rx_packet_seen", rx_packet_seen, 1'b1);
        expect_bit("adapter.saw_version_read", saw_version_read, 1'b1);
        expect_bit("adapter.saw_open_cmd", saw_open_cmd, 1'b1);
        expect_bit("adapter.saw_recv_cmd", saw_recv_cmd, 1'b1);
        expect_u32("adapter.frame_count", frame_count, UDP_ALLOW_LEN);
        expect_bit("adapter.frame_src_port", frame_src_port, 1'b0);

        $display("PASS: eth_controller_adapter_tb");
        $finish;
    end
endmodule
