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
    inout  wire [35:0] GPIO_0,
    inout  wire [5:0]  GPIO_1
);
    wire rst_n;
    wire start_init;
    wire w5500_a_int_n;
    wire w5500_a_reset_n;
    wire spi_a_sclk;
    wire spi_a_mosi;
    wire spi_a_miso;
    wire spi_a_cs_n;
    wire w5500_b_int_n;
    wire w5500_b_reset_n;
    wire spi_b_sclk;
    wire spi_b_mosi;
    wire spi_b_miso;
    wire spi_b_cs_n;
    wire uart_tx;
    wire [31:0] rx_count;
    wire [31:0] allow_count;
    wire [31:0] drop_count;
    wire init_done_a;
    wire init_done_b;
    wire init_error_a;
    wire init_error_b;
    wire init_done;
    wire init_error;
    wire rx_packet_seen_a;
    wire [3:0] adapter_a_debug_state;
    wire [3:0] adapter_b_debug_state;
    wire forwarder_overflow;
    wire tx_error_b;
    wire last_action_allow;
    wire [3:0] last_matched_rule_id;
    wire        rx_frame_valid;
    wire [7:0]  rx_frame_data;
    wire        rx_frame_sop;
    wire        rx_frame_eop;
    wire [0:0]  rx_frame_src_port;
    wire        rx_frame_ready;
    wire        tx_frame_valid;
    wire [7:0]  tx_frame_data;
    wire        tx_frame_sop;
    wire        tx_frame_eop;
    wire [0:0]  tx_frame_src_port;
    wire        tx_frame_ready;
    wire [31:0] tx_count_b;
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

    assign rst_n          = rst_sync[1];
    assign start_init     = start_init_sync[1];
    assign w5500_a_int_n  = w5500_int_sync[1];
    assign w5500_b_int_n  = GPIO_1[5];
    assign spi_a_miso     = GPIO_0[4];
    assign spi_b_miso     = GPIO_1[4];
    assign debug_page     = SW[3:1];
    assign init_done      = init_done_a && init_done_b;
    assign init_error     = init_error_a || init_error_b || tx_error_b;

    assign GPIO_0[0] = spi_a_sclk;
    assign GPIO_0[1] = spi_a_mosi;
    assign GPIO_0[2] = spi_a_cs_n;
    assign GPIO_0[3] = w5500_a_reset_n;
    assign GPIO_0[4] = 1'bz;
    assign GPIO_0[5] = 1'bz;
    assign GPIO_0[6] = uart_tx;
    assign GPIO_0[35:7] = {29{1'bz}};

    assign GPIO_1[0] = spi_b_sclk;
    assign GPIO_1[1] = spi_b_mosi;
    assign GPIO_1[2] = spi_b_cs_n;
    assign GPIO_1[3] = w5500_b_reset_n;
    assign GPIO_1[4] = 1'bz;
    assign GPIO_1[5] = 1'bz;

    assign LEDR[0] = init_done;
    assign LEDR[1] = init_error;
    assign LEDR[2] = rx_packet_seen_a;
    assign LEDR[6:3] = SW[4] ? adapter_b_debug_state : adapter_a_debug_state;
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
                hex3_value = adapter_a_debug_state;
                hex2_value = last_matched_rule_id;
                hex1_value = last_action_allow ? 4'hA : 4'hD;
                hex0_value = {forwarder_overflow, init_error, init_done, rx_packet_seen_a};
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
                hex1_value = tx_error_b ? 4'hE : adapter_b_debug_state;
                hex0_value = init_error ? 4'hE : (rx_packet_seen_a ? 4'h1 : 4'h0);
            end
            3'b101: begin
                hex3_value = tx_count_b[15:12];
                hex2_value = tx_count_b[11:8];
                hex1_value = tx_count_b[7:4];
                hex0_value = tx_count_b[3:0];
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

    firewall_telemetry_uart #(
        .CLKS_PER_BIT(434),
        .REPORT_INTERVAL_CYCLES(25_000_000)
    ) u_firewall_telemetry_uart (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .last_rule_id(last_matched_rule_id),
        .last_action_allow(last_action_allow),
        .tx_error(1'b0),
        .uart_tx(uart_tx)
    );

    ethernet_controller_adapter #(
        .STARTUP_WAIT_CYCLES(5_000_000),
        .RESET_ASSERT_CYCLES(500_000),
        .RESET_RELEASE_CYCLES(5_000_000),
        .RX_POLL_WAIT_CYCLES(50_000),
        .SPI_CLK_DIV(50),
        .MAX_FRAME_BYTES(2048)
    ) u_w5500_a_rx (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(w5500_a_reset_n),
        .w5500_int_n(w5500_a_int_n),
        .spi_sclk(spi_a_sclk),
        .spi_mosi(spi_a_mosi),
        .spi_miso(spi_a_miso),
        .spi_cs_n(spi_a_cs_n),
        .init_busy(),
        .init_done(init_done_a),
        .init_error(init_error_a),
        .rx_packet_seen(rx_packet_seen_a),
        .frame_valid(rx_frame_valid),
        .frame_data(rx_frame_data),
        .frame_sop(rx_frame_sop),
        .frame_eop(rx_frame_eop),
        .frame_src_port(rx_frame_src_port),
        .frame_ready(rx_frame_ready),
        .debug_state(adapter_a_debug_state)
    );

    firewall_forwarder #(
        .MAX_PKT_BYTES(2048)
    ) u_firewall_forwarder (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .in_valid(rx_frame_valid),
        .in_data(rx_frame_data),
        .in_sop(rx_frame_sop),
        .in_eop(rx_frame_eop),
        .in_src_port(rx_frame_src_port),
        .in_ready(rx_frame_ready),
        .out_valid(tx_frame_valid),
        .out_data(tx_frame_data),
        .out_sop(tx_frame_sop),
        .out_eop(tx_frame_eop),
        .out_src_port(tx_frame_src_port),
        .out_ready(tx_frame_ready),
        .rx_count(rx_count),
        .allow_count(allow_count),
        .drop_count(drop_count),
        .last_action_allow(last_action_allow),
        .last_matched_rule_id(last_matched_rule_id),
        .buffer_overflow(forwarder_overflow)
    );

    w5500_macraw_tx_adapter #(
        .STARTUP_WAIT_CYCLES(5_000_000),
        .RESET_ASSERT_CYCLES(500_000),
        .RESET_RELEASE_CYCLES(5_000_000),
        .SPI_CLK_DIV(50),
        .MAX_FRAME_BYTES(2048)
    ) u_w5500_b_tx (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .start_init(start_init),
        .w5500_reset_n(w5500_b_reset_n),
        .w5500_int_n(w5500_b_int_n),
        .spi_sclk(spi_b_sclk),
        .spi_mosi(spi_b_mosi),
        .spi_miso(spi_b_miso),
        .spi_cs_n(spi_b_cs_n),
        .frame_valid(tx_frame_valid),
        .frame_data(tx_frame_data),
        .frame_sop(tx_frame_sop),
        .frame_eop(tx_frame_eop),
        .frame_ready(tx_frame_ready),
        .init_busy(),
        .init_done(init_done_b),
        .init_error(init_error_b),
        .tx_count(tx_count_b),
        .tx_error(tx_error_b),
        .debug_state(adapter_b_debug_state)
    );
endmodule
