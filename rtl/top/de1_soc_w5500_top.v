`timescale 1ns/1ps

module de1_soc_w5500_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    inout  wire [35:0] GPIO_0
);
    wire rst_n;
    wire start_init;
    wire w5500_int_n;
    wire w5500_reset_n;
    wire spi_sclk;
    wire spi_mosi;
    wire spi_miso;
    wire spi_cs_n;
    wire [31:0] rx_count;
    wire [31:0] allow_count;
    wire [31:0] drop_count;
    wire init_done;
    wire init_error;
    wire rx_packet_seen;
    wire [3:0] adapter_debug_state;

    assign rst_n      = KEY[0];
    assign start_init = SW[0];
    assign w5500_int_n = GPIO_0[5];
    assign spi_miso    = GPIO_0[4];

    assign GPIO_0[0] = spi_sclk;
    assign GPIO_0[1] = spi_mosi;
    assign GPIO_0[2] = spi_cs_n;
    assign GPIO_0[3] = w5500_reset_n;

    assign GPIO_0[35:6] = 30'h3fffffff;

    assign LEDR[0] = init_done;
    assign LEDR[1] = init_error;
    assign LEDR[2] = rx_packet_seen;
    assign LEDR[6:3] = adapter_debug_state;
    assign LEDR[7] = rx_count[0];
    assign LEDR[8] = allow_count[0];
    assign LEDR[9] = drop_count[0];

    firewall_top u_firewall_top (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_int_n(w5500_int_n),
        .spi_miso(spi_miso),
        .w5500_reset_n(w5500_reset_n),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_cs_n(spi_cs_n),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .init_done(init_done),
        .init_error(init_error),
        .rx_packet_seen(rx_packet_seen),
        .adapter_debug_state(adapter_debug_state)
    );
endmodule
