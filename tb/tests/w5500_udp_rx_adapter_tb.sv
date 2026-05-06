`timescale 1ns/1ps

module w5500_udp_rx_adapter_tb;
    import fw_tb_pkg::*;

    localparam int PAYLOAD_LEN = 64;
    localparam int SYNTH_FRAME_LEN = 42 + PAYLOAD_LEN;

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
    logic [31:0] rx_commit_count;
    logic [31:0] rx_stream_byte_count;
    logic [15:0] last_rx_size_bytes;
    logic [15:0] last_frame_len_bytes;
    logic [7:0] phy_cfgr_value;
    logic [31:0] phy_read_count;
    logic [7:0] socket_mode_value;
    logic [7:0] socket_status_value;
    logic [47:0] shar_value;
    logic [31:0] sipr_value;
    logic [3:0] debug_state;
    logic saw_version_read;
    logic saw_open_cmd;
    logic saw_recv_cmd;
    integer frame_count;

    w5500_udp_rx_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .RESET_ASSERT_CYCLES(4),
        .RESET_RELEASE_CYCLES(4),
        .RX_POLL_WAIT_CYCLES(2),
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(512)
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
        .rx_commit_count(rx_commit_count),
        .rx_stream_byte_count(rx_stream_byte_count),
        .last_rx_size_bytes(last_rx_size_bytes),
        .last_frame_len_bytes(last_frame_len_bytes),
        .phy_cfgr_value(phy_cfgr_value),
        .phy_read_count(phy_read_count),
        .socket_mode_value(socket_mode_value),
        .socket_status_value(socket_status_value),
        .shar_value(shar_value),
        .sipr_value(sipr_value),
        .debug_state(debug_state)
    );

    w5500_udp_rx_model #(
        .PACKET_FILE(UDP_ALLOW_MEM),
        .PACKET_LENGTH(UDP_ALLOW_LEN),
        .PAYLOAD_LENGTH(PAYLOAD_LEN),
        .PACKET_SOCKET(1)
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

    function automatic [15:0] ipv4_check(input int payload_len);
        logic [31:0] sum;
        logic [31:0] folded;
        begin
            sum = 32'h00004500 + {16'd0, 16'(28 + payload_len)} + 32'h00004011 +
                  32'h0000c0a8 + 32'h0000010a + 32'h0000c0a8 + 32'h00000101;
            folded = {16'd0, sum[15:0]} + {16'd0, sum[31:16]};
            folded = {16'd0, folded[15:0]} + {16'd0, folded[31:16]};
            ipv4_check = ~folded[15:0];
        end
    endfunction

    function automatic [7:0] expected_byte(input int idx);
        logic [15:0] ip_check;
        logic [15:0] ip_total_len;
        logic [15:0] udp_len;
        begin
            ip_check = ipv4_check(PAYLOAD_LEN);
            ip_total_len = 16'(28 + PAYLOAD_LEN);
            udp_len = 16'(8 + PAYLOAD_LEN);
            case (idx)
                0, 1, 2, 3, 4, 5: expected_byte = 8'hff;
                6:  expected_byte = 8'h00;
                7:  expected_byte = 8'h11;
                8:  expected_byte = 8'h22;
                9:  expected_byte = 8'h33;
                10: expected_byte = 8'h44;
                11: expected_byte = 8'h55;
                12: expected_byte = 8'h08;
                13: expected_byte = 8'h00;
                14: expected_byte = 8'h45;
                15: expected_byte = 8'h00;
                16: expected_byte = ip_total_len[15:8];
                17: expected_byte = ip_total_len[7:0];
                18, 19, 20, 21: expected_byte = 8'h00;
                22: expected_byte = 8'h40;
                23: expected_byte = 8'h11;
                24: expected_byte = ip_check[15:8];
                25: expected_byte = ip_check[7:0];
                26: expected_byte = 8'hc0;
                27: expected_byte = 8'ha8;
                28: expected_byte = 8'h01;
                29: expected_byte = 8'h0a;
                30: expected_byte = 8'hc0;
                31: expected_byte = 8'ha8;
                32: expected_byte = 8'h01;
                33: expected_byte = 8'h01;
                34: expected_byte = 8'h12;
                35: expected_byte = 8'h34;
                36: expected_byte = 8'h13;
                37: expected_byte = 8'h89;
                38: expected_byte = udp_len[15:8];
                39: expected_byte = udp_len[7:0];
                40: expected_byte = 8'h00;
                41: expected_byte = 8'h00;
                default: expected_byte = ((idx - 42) & 8'hff) ^ 8'ha5;
            endcase
        end
    endfunction

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (frame_valid && frame_ready) begin
            if (frame_data !== expected_byte(frame_count)) begin
                $error("udp adapter frame byte mismatch idx=%0d got=0x%02h expected=0x%02h",
                       frame_count, frame_data, expected_byte(frame_count));
                $fatal(1);
            end
            if (frame_sop !== (frame_count == 0)) begin
                $error("udp adapter SOP mismatch idx=%0d", frame_count);
                $fatal(1);
            end
            if (frame_eop !== (frame_count == (SYNTH_FRAME_LEN - 1))) begin
                $error("udp adapter EOP mismatch idx=%0d", frame_count);
                $fatal(1);
            end
            frame_count = frame_count + 1;
        end
    end

    initial begin
        rst_n       = 1'b0;
        start_init  = 1'b0;
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

        expect_bit("udp_adapter.init_error", init_error, 1'b0);
        expect_bit("udp_adapter.rx_packet_seen", rx_packet_seen, 1'b1);
        expect_bit("udp_adapter.saw_version_read", saw_version_read, 1'b1);
        expect_bit("udp_adapter.saw_open_cmd", saw_open_cmd, 1'b1);
        expect_bit("udp_adapter.saw_recv_cmd", saw_recv_cmd, 1'b1);
        expect_u32("udp_adapter.frame_count", frame_count, SYNTH_FRAME_LEN);
        expect_u32("udp_adapter.rx_commit_count", rx_commit_count, 32'd1);
        expect_u32("udp_adapter.rx_stream_byte_count", rx_stream_byte_count, SYNTH_FRAME_LEN);
        expect_u16("udp_adapter.last_rx_size", last_rx_size_bytes, 16'(8 + PAYLOAD_LEN));
        expect_u16("udp_adapter.last_frame_len", last_frame_len_bytes, SYNTH_FRAME_LEN);
        expect_u8("udp_adapter.phy_cfgr", phy_cfgr_value, 8'hbf);
        expect_u8("udp_adapter.socket_mode", socket_mode_value, 8'h02);
        expect_u8("udp_adapter.socket_status", socket_status_value, 8'h22);
        expect_u32("udp_adapter.sipr", sipr_value, 32'hc0a80101);
        expect_bit("udp_adapter.frame_src_port", frame_src_port, 1'b1);

        $display("PASS: w5500_udp_rx_adapter_tb");
        $finish;
    end
endmodule
