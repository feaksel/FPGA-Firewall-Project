`timescale 1ns/1ps

module adapter_firewall_integration_tb;
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
    logic [31:0] rx_count;
    logic [31:0] allow_count;
    logic [31:0] drop_count;
    logic last_action_allow;
    logic [3:0] last_matched_rule_id;

    ethernet_controller_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .RESET_ASSERT_CYCLES(4),
        .RESET_RELEASE_CYCLES(4),
        .RX_POLL_WAIT_CYCLES(2),
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(64)
    ) u_adapter (
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
        .debug_state(debug_state)
    );

    firewall_core u_firewall_core (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(frame_valid),
        .in_data(frame_data),
        .in_sop(frame_sop),
        .in_eop(frame_eop),
        .in_src_port(frame_src_port),
        .in_ready(frame_ready),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id)
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
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n      = 1'b0;
        start_init = 1'b0;

        #30;
        rst_n = 1'b1;

        @(posedge clk);
        start_init = 1'b1;
        @(posedge clk);
        start_init = 1'b0;

        wait(allow_count == 32'd1);
        wait(rx_packet_seen);
        @(negedge clk);

        expect_bit("integration.init_error", init_error, 1'b0);
        expect_bit("integration.rx_packet_seen", rx_packet_seen, 1'b1);
        expect_u32("integration.rx_count", rx_count, 32'd1);
        expect_u32("integration.allow_count", allow_count, 32'd1);
        expect_u32("integration.drop_count", drop_count, 32'd0);
        expect_bit("integration.last_action_allow", last_action_allow, 1'b1);
        expect_u4("integration.last_matched_rule_id", last_matched_rule_id, 4'd0);
        expect_bit("integration.saw_version_read", saw_version_read, 1'b1);
        expect_bit("integration.saw_open_cmd", saw_open_cmd, 1'b1);
        expect_bit("integration.saw_recv_cmd", saw_recv_cmd, 1'b1);

        $display("PASS: adapter_firewall_integration_tb");
        $finish;
    end
endmodule
