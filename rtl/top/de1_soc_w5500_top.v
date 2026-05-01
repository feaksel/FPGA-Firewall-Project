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
    wire rx_fifo_overflow;
    reg  [1:0] rst_sync;
    reg  [1:0] start_init_sync;
    reg  [1:0] w5500_int_sync;

    always @(posedge CLOCK_50 or negedge KEY[0]) begin
        if (!KEY[0])
            rst_sync <= 2'b00;
        else
            rst_sync <= {rst_sync[0], 1'b1};
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            start_init_sync <= 2'b00;
            w5500_int_sync  <= 2'b11;
        end else begin
            start_init_sync <= {start_init_sync[0], SW[0]};
            w5500_int_sync  <= {w5500_int_sync[0], GPIO_0[5]};
        end
    end

    assign rst_n       = rst_sync[1];
    assign start_init  = start_init_sync[1];
    assign w5500_int_n = w5500_int_sync[1];
    assign spi_miso    = GPIO_0[4];

    assign GPIO_0[0] = spi_sclk;
    assign GPIO_0[1] = spi_mosi;
    assign GPIO_0[2] = spi_cs_n;
    assign GPIO_0[3] = w5500_reset_n;
    assign GPIO_0[4] = 1'bz;
    assign GPIO_0[5] = 1'bz;
    assign GPIO_0[35:6] = {30{1'bz}};

    assign LEDR[0] = init_done;
    assign LEDR[1] = init_error;
    assign LEDR[2] = rx_packet_seen;
    assign LEDR[6:3] = adapter_debug_state;
    assign LEDR[7] = rx_count[0];
    assign LEDR[8] = allow_count[0];
    assign LEDR[9] = drop_count[0];

    firewall_top #(
        .STARTUP_WAIT_CYCLES(5_000_000),
        .RESET_ASSERT_CYCLES(500_000),
        .RESET_RELEASE_CYCLES(5_000_000),
        .RX_POLL_WAIT_CYCLES(50_000),
        .SPI_CLK_DIV(50),
        .MAX_FRAME_BYTES(2048)
    ) u_firewall_top (
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
        .adapter_debug_state(adapter_debug_state),
        .rx_fifo_overflow(rx_fifo_overflow)
    );
endmodule
