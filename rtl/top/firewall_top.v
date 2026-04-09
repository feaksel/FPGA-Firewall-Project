`timescale 1ns/1ps

module firewall_top (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_init,
    input  wire        spi_miso,
    output wire        spi_sclk,
    output wire        spi_mosi,
    output wire        spi_cs_n,
    output wire [31:0] rx_count,
    output wire [31:0] allow_count,
    output wire [31:0] drop_count,
    output wire [3:0]  adapter_debug_state
);
    wire        frame_valid;
    wire [7:0]  frame_data;
    wire        frame_sop;
    wire        frame_eop;
    wire [0:0]  frame_src_port;
    wire        frame_ready;
    wire        init_busy;
    wire        init_done;
    wire        init_error;
    wire        last_action_allow;
    wire [3:0]  last_matched_rule_id;

    ethernet_controller_adapter u_adapter (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .init_busy(init_busy),
        .init_done(init_done),
        .init_error(init_error),
        .frame_valid(frame_valid),
        .frame_data(frame_data),
        .frame_sop(frame_sop),
        .frame_eop(frame_eop),
        .frame_src_port(frame_src_port),
        .frame_ready(frame_ready),
        .debug_state(adapter_debug_state)
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
endmodule
