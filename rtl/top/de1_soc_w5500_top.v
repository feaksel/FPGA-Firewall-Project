`timescale 1ns/1ps

module de1_soc_w5500_top (
    input  wire        CLOCK_50,
    input  wire [3:0]  KEY,
    input  wire [9:0]  SW,
    output wire [9:0]  LEDR,
    output wire [6:0]  HEX0,
    output wire [6:0]  HEX1,
    output wire [6:0]  HEX2,
    output wire [6:0]  HEX3,
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
    wire last_action_allow;
    wire [3:0] last_matched_rule_id;
    wire [2:0] debug_page;
    reg  [3:0] hex0_value;
    reg  [3:0] hex1_value;
    reg  [3:0] hex2_value;
    reg  [3:0] hex3_value;
    reg        hex_blank;
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
    assign debug_page  = SW[3:1];

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

    always @* begin
        hex0_value = 4'h0;
        hex1_value = 4'h0;
        hex2_value = 4'h0;
        hex3_value = 4'h0;
        hex_blank  = 1'b0;

        case (debug_page)
            3'b000: begin
                hex3_value = adapter_debug_state;
                hex2_value = last_matched_rule_id;
                hex1_value = last_action_allow ? 4'hA : 4'hD;
                hex0_value = {rx_fifo_overflow, init_error, init_done, rx_packet_seen};
            end
            3'b001: begin
                hex3_value = rx_count[15:12];
                hex2_value = rx_count[11:8];
                hex1_value = rx_count[7:4];
                hex0_value = rx_count[3:0];
            end
            3'b010: begin
                hex3_value = allow_count[15:12];
                hex2_value = allow_count[11:8];
                hex1_value = allow_count[7:4];
                hex0_value = allow_count[3:0];
            end
            3'b011: begin
                hex3_value = drop_count[15:12];
                hex2_value = drop_count[11:8];
                hex1_value = drop_count[7:4];
                hex0_value = drop_count[3:0];
            end
            3'b100: begin
                hex3_value = last_matched_rule_id;
                hex2_value = last_action_allow ? 4'hA : 4'hD;
                hex1_value = rx_fifo_overflow ? 4'hF : 4'h0;
                hex0_value = init_error ? 4'hE : (rx_packet_seen ? 4'h1 : 4'h0);
            end
            default: begin
                hex_blank = 1'b1;
            end
        endcase
    end

    seven_seg_hex u_hex0 (
        .value(hex0_value),
        .blank(hex_blank),
        .segments_n(HEX0)
    );

    seven_seg_hex u_hex1 (
        .value(hex1_value),
        .blank(hex_blank),
        .segments_n(HEX1)
    );

    seven_seg_hex u_hex2 (
        .value(hex2_value),
        .blank(hex_blank),
        .segments_n(HEX2)
    );

    seven_seg_hex u_hex3 (
        .value(hex3_value),
        .blank(hex_blank),
        .segments_n(HEX3)
    );

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
        .rx_fifo_overflow(rx_fifo_overflow),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id)
    );
endmodule
