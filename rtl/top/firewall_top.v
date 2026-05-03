`timescale 1ns/1ps

module firewall_top #(
    parameter USE_RX_FIFO          = 1,
    parameter STARTUP_WAIT_CYCLES  = 16,
    parameter RESET_ASSERT_CYCLES  = 16,
    parameter RESET_RELEASE_CYCLES = 32,
    parameter RX_POLL_WAIT_CYCLES  = 32,
    parameter SPI_CLK_DIV          = 4,
    parameter MAX_FRAME_BYTES      = 512,
    parameter RX_FIFO_PACKET_DEPTH = 4,
    parameter RX_FIFO_MAX_PKT_BYTES = 2048
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_init,
    input  wire        w5500_int_n,
    input  wire        spi_miso,
    output wire        w5500_reset_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    output wire        spi_cs_n,
    output wire [31:0] rx_count,
    output wire [31:0] allow_count,
    output wire [31:0] drop_count,
    output wire        init_done,
    output wire        init_error,
    output wire        rx_packet_seen,
    output wire [3:0]  adapter_debug_state,
    output wire        rx_fifo_overflow,
    output wire        last_action_allow,
    output wire [3:0]  last_matched_rule_id
);
    wire        adapter_frame_valid;
    wire [7:0]  adapter_frame_data;
    wire        adapter_frame_sop;
    wire        adapter_frame_eop;
    wire [0:0]  adapter_frame_src_port;
    wire        adapter_frame_ready;
    wire        core_frame_valid;
    wire [7:0]  core_frame_data;
    wire        core_frame_sop;
    wire        core_frame_eop;
    wire [0:0]  core_frame_src_port;
    wire        core_frame_ready;
    wire        fifo_overflow_int;

    ethernet_controller_adapter u_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(w5500_reset_n),
        .w5500_int_n(w5500_int_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .init_busy(),
        .init_done(init_done),
        .init_error(init_error),
        .rx_packet_seen(rx_packet_seen),
        .frame_valid(adapter_frame_valid),
        .frame_data(adapter_frame_data),
        .frame_sop(adapter_frame_sop),
        .frame_eop(adapter_frame_eop),
        .frame_src_port(adapter_frame_src_port),
        .frame_ready(adapter_frame_ready),
        .rx_commit_count(),
        .rx_stream_byte_count(),
        .last_rx_size_bytes(),
        .last_frame_len_bytes(),
        .debug_state(adapter_debug_state)
    );

    defparam u_adapter.STARTUP_WAIT_CYCLES  = STARTUP_WAIT_CYCLES;
    defparam u_adapter.RESET_ASSERT_CYCLES  = RESET_ASSERT_CYCLES;
    defparam u_adapter.RESET_RELEASE_CYCLES = RESET_RELEASE_CYCLES;
    defparam u_adapter.RX_POLL_WAIT_CYCLES  = RX_POLL_WAIT_CYCLES;
    defparam u_adapter.SPI_CLK_DIV          = SPI_CLK_DIV;
    defparam u_adapter.MAX_FRAME_BYTES      = MAX_FRAME_BYTES;

    generate
        if (USE_RX_FIFO) begin : g_use_rx_fifo
            frame_rx_fifo #(
                .PACKET_DEPTH(RX_FIFO_PACKET_DEPTH),
                .MAX_PKT_BYTES(RX_FIFO_MAX_PKT_BYTES)
            ) u_rx_fifo (
                .clk(clk),
                .rst_n(rst_n),
                .in_valid(adapter_frame_valid),
                .in_data(adapter_frame_data),
                .in_sop(adapter_frame_sop),
                .in_eop(adapter_frame_eop),
                .in_src_port(adapter_frame_src_port),
                .in_ready(adapter_frame_ready),
                .out_valid(core_frame_valid),
                .out_data(core_frame_data),
                .out_sop(core_frame_sop),
                .out_eop(core_frame_eop),
                .out_src_port(core_frame_src_port),
                .out_ready(core_frame_ready),
                .overflow_error(fifo_overflow_int)
            );
        end else begin : g_bypass_rx_fifo
            assign core_frame_valid    = adapter_frame_valid;
            assign core_frame_data     = adapter_frame_data;
            assign core_frame_sop      = adapter_frame_sop;
            assign core_frame_eop      = adapter_frame_eop;
            assign core_frame_src_port = adapter_frame_src_port;
            assign adapter_frame_ready = core_frame_ready;
            assign fifo_overflow_int   = 1'b0;
        end
    endgenerate

    assign rx_fifo_overflow = fifo_overflow_int;

    firewall_core u_firewall_core (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(core_frame_valid),
        .in_data(core_frame_data),
        .in_sop(core_frame_sop),
        .in_eop(core_frame_eop),
        .in_src_port(core_frame_src_port),
        .in_ready(core_frame_ready),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id)
    );
endmodule
