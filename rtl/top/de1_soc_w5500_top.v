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
    reg  [31:0] raw_rx_count;
    wire [31:0] display_rx_count;
    wire [31:0] rx_commit_count_a;
    wire [31:0] rx_stream_byte_count_a;
    wire [15:0] last_rx_size_bytes_a;
    wire [15:0] last_frame_len_bytes_a;
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
    wire [4:0] adapter_b_debug_state;
    wire [15:0] b_last_pkt_len;
    wire        b_pkt_available;
    wire [31:0] b_buf_write_start_count;
    wire [31:0] b_send_issued_count;
    wire [31:0] b_send_cleared_count;
    wire [31:0] b_send_timeout_count;
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
    wire        rx_fifo_in_ready;
    wire        rx_fifo_overflow;
    wire        core_frame_valid;
    wire [7:0]  core_frame_data;
    wire        core_frame_sop;
    wire        core_frame_eop;
    wire [0:0]  core_frame_src_port;
    wire        core_frame_ready;
    wire        rx_drain_debug;
    wire        tx_test_mode;
    wire        forward_bypass_mode;
    wire        rule_regen_mode;
    wire        synthetic_tx_mode;
    wire        tx_frame_valid;
    wire [7:0]  tx_frame_data;
    wire        tx_frame_sop;
    wire        tx_frame_eop;
    wire [0:0]  tx_frame_src_port;
    wire        tx_frame_ready;
    wire        tx_to_b_valid;
    wire [7:0]  tx_to_b_data;
    wire        tx_to_b_sop;
    wire        tx_to_b_eop;
    wire        forwarder_out_ready;
    wire        fifo_out_ready;
    wire        middle_frame_valid;
    wire [7:0]  middle_frame_data;
    wire        middle_frame_sop;
    wire        middle_frame_eop;
    wire [31:0] tx_count_b;
    reg         tx_test_valid;
    reg  [7:0]  tx_test_data;
    reg         tx_test_sop;
    reg         tx_test_eop;
    reg  [7:0]  tx_test_index;
    reg  [31:0] tx_test_wait_ctr;
    reg  [31:0] tx_test_count;
    reg         regen_allow_pending;
    reg  [15:0] regen_byte_index;
    reg  [15:0] regen_ethertype;
    reg  [7:0]  regen_ip_proto;
    reg  [15:0] regen_dst_port;
    reg  [31:0] regen_allow_count;
    reg  [31:0] regen_drop_count;
    reg  [31:0] regen_frames_seen;
    reg  [15:0] regen_last_eop_byte_idx;
    reg  [15:0] regen_max_byte_idx;
    reg  [15:0] rx_per_frame_byte_idx;
    reg  [15:0] rx_probe_byte_index;
    reg  [15:0] rx_probe_ethertype;
    reg  [7:0]  rx_probe_ip_proto;
    reg  [15:0] rx_probe_dst_port;
    reg  [7:0]  a_rx_capture [0:15];
    reg  [7:0]  a_rx_shadow  [0:15];
    reg  [4:0]  a_rx_capture_idx;
    reg  [7:0]  b_tx_capture [0:15];
    reg  [7:0]  b_tx_shadow  [0:15];
    reg  [4:0]  b_tx_capture_idx;
    reg         ever_b_eop_in;
    reg         ever_b_buf_write;
    reg         ever_b_send_issued;
    reg         ever_b_send_cleared;
    reg         ever_b_send_timeout;
    reg         ever_b_in_st_ready;
    reg  [31:0] b_eop_in_count;
    wire        byte_dbg_mode;
    wire [1:0]  view_bank;
    wire [2:0] debug_page;
    reg  [3:0] hex0_value;
    reg  [3:0] hex1_value;
    reg  [3:0] hex2_value;
    reg  [3:0] hex3_value;
    reg        hex_blank;
    reg  [1:0] rst_sync;
    reg  [1:0] start_init_sync;
    reg  [1:0] w5500_int_sync;

    (* preserve, noprune *) reg [7:0]   stp_rx_data;
    (* preserve, noprune *) reg [4:0]   stp_rx_ctrl;
    (* preserve, noprune *) reg [7:0]   stp_tx_b_data;
    (* preserve, noprune *) reg [4:0]   stp_tx_b_ctrl;
    (* preserve, noprune *) reg [4:0]   stp_adapter_b_state;
    (* preserve, noprune *) reg [3:0]   stp_adapter_a_state;
    (* preserve, noprune *) reg [31:0]  stp_b_buf_writes;
    (* preserve, noprune *) reg [31:0]  stp_b_send_issued;
    (* preserve, noprune *) reg [31:0]  stp_b_send_cleared;
    (* preserve, noprune *) reg [31:0]  stp_b_send_timeouts;
    (* preserve, noprune *) reg [31:0]  stp_b_tx_count;
    (* preserve, noprune *) reg [15:0]  stp_b_last_pkt_len;
    (* preserve, noprune *) reg [7:0]   stp_b_status;
    (* preserve, noprune *) reg [3:0]   stp_spi_b;
    (* preserve, noprune *) reg [9:0]   stp_switches;
    (* preserve, noprune *) reg [127:0] stp_a_rx_first16;
    (* preserve, noprune *) reg [127:0] stp_b_tx_first16;
    (* preserve, noprune *) reg [15:0]  stp_regen_ethertype;
    (* preserve, noprune *) reg [7:0]   stp_regen_ip_proto;
    (* preserve, noprune *) reg [15:0]  stp_regen_dst_port;

    always @(posedge CLOCK_50) begin
        stp_rx_data <= rx_frame_data;
        stp_rx_ctrl <= {rx_frame_valid, rx_frame_ready, rx_frame_sop, rx_frame_eop, rx_packet_seen_a};
        stp_tx_b_data <= tx_to_b_data;
        stp_tx_b_ctrl <= {tx_to_b_valid, tx_frame_ready, tx_to_b_sop, tx_to_b_eop, b_pkt_available};
        stp_adapter_b_state <= adapter_b_debug_state;
        stp_adapter_a_state <= adapter_a_debug_state;
        stp_b_buf_writes <= b_buf_write_start_count;
        stp_b_send_issued <= b_send_issued_count;
        stp_b_send_cleared <= b_send_cleared_count;
        stp_b_send_timeouts <= b_send_timeout_count;
        stp_b_tx_count <= tx_count_b;
        stp_b_last_pkt_len <= b_last_pkt_len;
        stp_b_status <= {tx_error_b, ever_b_send_timeout, ever_b_send_cleared,
                         ever_b_send_issued, ever_b_buf_write, ever_b_eop_in,
                         b_pkt_available, init_error_b};
        stp_spi_b <= {spi_b_cs_n, spi_b_sclk, spi_b_mosi, spi_b_miso};
        stp_switches <= SW;
        stp_a_rx_first16 <= {a_rx_shadow[0], a_rx_shadow[1], a_rx_shadow[2], a_rx_shadow[3],
                             a_rx_shadow[4], a_rx_shadow[5], a_rx_shadow[6], a_rx_shadow[7],
                             a_rx_shadow[8], a_rx_shadow[9], a_rx_shadow[10], a_rx_shadow[11],
                             a_rx_shadow[12], a_rx_shadow[13], a_rx_shadow[14], a_rx_shadow[15]};
        stp_b_tx_first16 <= {b_tx_shadow[0], b_tx_shadow[1], b_tx_shadow[2], b_tx_shadow[3],
                             b_tx_shadow[4], b_tx_shadow[5], b_tx_shadow[6], b_tx_shadow[7],
                             b_tx_shadow[8], b_tx_shadow[9], b_tx_shadow[10], b_tx_shadow[11],
                             b_tx_shadow[12], b_tx_shadow[13], b_tx_shadow[14], b_tx_shadow[15]};
        stp_regen_ethertype <= rule_regen_mode ? regen_ethertype : rx_probe_ethertype;
        stp_regen_ip_proto <= rule_regen_mode ? regen_ip_proto : rx_probe_ip_proto;
        stp_regen_dst_port <= rule_regen_mode ? regen_dst_port : rx_probe_dst_port;
    end

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
    assign byte_dbg_mode  = SW[9];
    assign view_bank      = byte_dbg_mode ? {SW[5], SW[4]} : 2'b00;
    assign rx_drain_debug = !byte_dbg_mode && SW[5];
    assign tx_test_mode   = SW[6];
    assign forward_bypass_mode = SW[7];
    assign rule_regen_mode = SW[8];
    assign synthetic_tx_mode = tx_test_mode || rule_regen_mode;
    assign rx_frame_ready = rx_drain_debug ? 1'b1 :
                            (rule_regen_mode ? 1'b1 :
                            (forward_bypass_mode ? tx_frame_ready : rx_fifo_in_ready));
    assign display_rx_count = (rx_drain_debug || rule_regen_mode) ? raw_rx_count : rx_count;
    assign init_done      = init_done_a && init_done_b;
    assign init_error     = init_error_a || init_error_b || tx_error_b;
    assign fifo_out_ready = forward_bypass_mode ? 1'b0 : core_frame_ready;
    assign middle_frame_valid = forward_bypass_mode ? rx_frame_valid : tx_frame_valid;
    assign middle_frame_data  = forward_bypass_mode ? rx_frame_data  : tx_frame_data;
    assign middle_frame_sop   = forward_bypass_mode ? rx_frame_sop   : tx_frame_sop;
    assign middle_frame_eop   = forward_bypass_mode ? rx_frame_eop   : tx_frame_eop;
    assign tx_to_b_valid  = synthetic_tx_mode ? tx_test_valid : middle_frame_valid;
    assign tx_to_b_data   = synthetic_tx_mode ? tx_test_data  : middle_frame_data;
    assign tx_to_b_sop    = synthetic_tx_mode ? tx_test_sop   : middle_frame_sop;
    assign tx_to_b_eop    = synthetic_tx_mode ? tx_test_eop   : middle_frame_eop;
    assign forwarder_out_ready = synthetic_tx_mode ? 1'b0 : tx_frame_ready;

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
    assign LEDR[6:3] = byte_dbg_mode ? {ever_b_send_timeout, ever_b_send_cleared, ever_b_send_issued, ever_b_buf_write}
                                     : (SW[4] ? adapter_b_debug_state[3:0] : adapter_a_debug_state);
    assign LEDR[7] = byte_dbg_mode ? ever_b_eop_in
                                   : (SW[4] ? tx_to_b_valid : rx_count[0]);
    assign LEDR[8] = byte_dbg_mode ? b_pkt_available
                                   : (SW[4] ? tx_frame_ready : rx_stream_byte_count_a[0]);
    assign LEDR[9] = byte_dbg_mode ? tx_error_b
                                   : (SW[4] ? rx_fifo_overflow : rx_commit_count_a[0]);

    always @* begin
        hex0_value = 4'h0;
        hex1_value = 4'h0;
        hex2_value = 4'h0;
        hex3_value = 4'h0;
        hex_blank  = 1'b0;

        if (byte_dbg_mode) begin
            case (view_bank)
                2'b00: begin
                    hex3_value = a_rx_shadow[{debug_page, 1'b0}][7:4];
                    hex2_value = a_rx_shadow[{debug_page, 1'b0}][3:0];
                    hex1_value = a_rx_shadow[{debug_page, 1'b1}][7:4];
                    hex0_value = a_rx_shadow[{debug_page, 1'b1}][3:0];
                end
                2'b01: begin
                    hex3_value = b_tx_shadow[{debug_page, 1'b0}][7:4];
                    hex2_value = b_tx_shadow[{debug_page, 1'b0}][3:0];
                    hex1_value = b_tx_shadow[{debug_page, 1'b1}][7:4];
                    hex0_value = b_tx_shadow[{debug_page, 1'b1}][3:0];
                end
                2'b10: begin
                    case (debug_page)
                        3'b000: begin
                            hex3_value = {tx_error_b, ever_b_send_timeout, ever_b_send_cleared, ever_b_send_issued};
                            hex2_value = {ever_b_buf_write, ever_b_eop_in, ever_b_in_st_ready, b_pkt_available};
                            hex1_value = {init_done_a, init_done_b, init_error_a, init_error_b};
                            hex0_value = {rx_packet_seen_a, forwarder_overflow, rx_fifo_overflow, 1'b0};
                        end
                        3'b001: begin
                            hex3_value = {3'b000, adapter_b_debug_state[4]};
                            hex2_value = adapter_b_debug_state[3:0];
                            hex1_value = 4'h0;
                            hex0_value = adapter_a_debug_state;
                        end
                        3'b010: begin
                            hex3_value = b_buf_write_start_count[15:12];
                            hex2_value = b_buf_write_start_count[11:8];
                            hex1_value = b_buf_write_start_count[7:4];
                            hex0_value = b_buf_write_start_count[3:0];
                        end
                        3'b011: begin
                            hex3_value = b_send_issued_count[15:12];
                            hex2_value = b_send_issued_count[11:8];
                            hex1_value = b_send_issued_count[7:4];
                            hex0_value = b_send_issued_count[3:0];
                        end
                        3'b100: begin
                            hex3_value = b_send_cleared_count[15:12];
                            hex2_value = b_send_cleared_count[11:8];
                            hex1_value = b_send_cleared_count[7:4];
                            hex0_value = b_send_cleared_count[3:0];
                        end
                        3'b101: begin
                            hex3_value = b_send_timeout_count[15:12];
                            hex2_value = b_send_timeout_count[11:8];
                            hex1_value = b_send_timeout_count[7:4];
                            hex0_value = b_send_timeout_count[3:0];
                        end
                        3'b110: begin
                            hex3_value = tx_count_b[15:12];
                            hex2_value = tx_count_b[11:8];
                            hex1_value = tx_count_b[7:4];
                            hex0_value = tx_count_b[3:0];
                        end
                        3'b111: begin
                            hex3_value = b_last_pkt_len[15:12];
                            hex2_value = b_last_pkt_len[11:8];
                            hex1_value = b_last_pkt_len[7:4];
                            hex0_value = b_last_pkt_len[3:0];
                        end
                        default: hex_blank = 1'b1;
                    endcase
                end
                2'b11: begin
                    case (debug_page)
                        3'b000: begin
                            hex3_value = regen_ethertype[15:12];
                            hex2_value = regen_ethertype[11:8];
                            hex1_value = regen_ethertype[7:4];
                            hex0_value = regen_ethertype[3:0];
                        end
                        3'b001: begin
                            hex3_value = 4'h0;
                            hex2_value = 4'h0;
                            hex1_value = regen_ip_proto[7:4];
                            hex0_value = regen_ip_proto[3:0];
                        end
                        3'b010: begin
                            hex3_value = regen_dst_port[15:12];
                            hex2_value = regen_dst_port[11:8];
                            hex1_value = regen_dst_port[7:4];
                            hex0_value = regen_dst_port[3:0];
                        end
                        3'b011: begin
                            hex3_value = regen_allow_count[15:12];
                            hex2_value = regen_allow_count[11:8];
                            hex1_value = regen_allow_count[7:4];
                            hex0_value = regen_allow_count[3:0];
                        end
                        3'b100: begin
                            hex3_value = regen_drop_count[15:12];
                            hex2_value = regen_drop_count[11:8];
                            hex1_value = regen_drop_count[7:4];
                            hex0_value = regen_drop_count[3:0];
                        end
                        3'b101: begin
                            hex3_value = regen_frames_seen[15:12];
                            hex2_value = regen_frames_seen[11:8];
                            hex1_value = regen_frames_seen[7:4];
                            hex0_value = regen_frames_seen[3:0];
                        end
                        3'b110: begin
                            hex3_value = regen_last_eop_byte_idx[15:12];
                            hex2_value = regen_last_eop_byte_idx[11:8];
                            hex1_value = regen_last_eop_byte_idx[7:4];
                            hex0_value = regen_last_eop_byte_idx[3:0];
                        end
                        3'b111: begin
                            hex3_value = regen_max_byte_idx[15:12];
                            hex2_value = regen_max_byte_idx[11:8];
                            hex1_value = regen_max_byte_idx[7:4];
                            hex0_value = regen_max_byte_idx[3:0];
                        end
                        default: hex_blank = 1'b1;
                    endcase
                end
                default: hex_blank = 1'b1;
            endcase
        end else if (rx_drain_debug) begin
            case (debug_page)
                3'b000: begin
                    hex3_value = adapter_a_debug_state;
                    hex2_value = 4'h5;
                    hex1_value = 4'h0;
                    hex0_value = {forwarder_overflow, init_error, init_done, rx_packet_seen_a};
                end
                3'b001: begin
                    hex3_value = rx_stream_byte_count_a[15:12];
                    hex2_value = rx_stream_byte_count_a[11:8];
                    hex1_value = rx_stream_byte_count_a[7:4];
                    hex0_value = rx_stream_byte_count_a[3:0];
                end
                3'b010: begin
                    hex3_value = rx_commit_count_a[15:12];
                    hex2_value = rx_commit_count_a[11:8];
                    hex1_value = rx_commit_count_a[7:4];
                    hex0_value = rx_commit_count_a[3:0];
                end
                3'b011: begin
                    hex3_value = last_rx_size_bytes_a[15:12];
                    hex2_value = last_rx_size_bytes_a[11:8];
                    hex1_value = last_rx_size_bytes_a[7:4];
                    hex0_value = last_rx_size_bytes_a[3:0];
                end
                3'b100: begin
                    hex3_value = last_frame_len_bytes_a[15:12];
                    hex2_value = last_frame_len_bytes_a[11:8];
                    hex1_value = last_frame_len_bytes_a[7:4];
                    hex0_value = last_frame_len_bytes_a[3:0];
                end
                3'b101: begin
                    hex3_value = raw_rx_count[15:12];
                    hex2_value = raw_rx_count[11:8];
                    hex1_value = raw_rx_count[7:4];
                    hex0_value = raw_rx_count[3:0];
                end
                3'b110: begin
                    hex3_value = {3'b000, w5500_a_int_n};
                    hex2_value = {3'b000, spi_a_cs_n};
                    hex1_value = {3'b000, spi_a_sclk};
                    hex0_value = {3'b000, spi_a_miso};
                end
                3'b111: begin
                    hex3_value = 4'h5;
                    hex2_value = rx_stream_byte_count_a[3:0];
                    hex1_value = rx_commit_count_a[3:0];
                    hex0_value = raw_rx_count[3:0];
                end
                default: begin
                    hex_blank = 1'b1;
                end
            endcase
        end else begin
        case (debug_page)
            3'b000: begin
                hex3_value = adapter_a_debug_state;
                hex2_value = last_matched_rule_id;
                hex1_value = last_action_allow ? 4'hA : 4'hD;
                hex0_value = {forwarder_overflow, init_error, init_done, rx_packet_seen_a};
            end
            3'b001: begin
                hex3_value = display_rx_count[15:12];
                hex2_value = display_rx_count[11:8];
                hex1_value = display_rx_count[7:4];
                hex0_value = display_rx_count[3:0];
            end
            3'b010: begin
                hex3_value = rule_regen_mode ? regen_allow_count[15:12] : allow_count[15:12];
                hex2_value = rule_regen_mode ? regen_allow_count[11:8]  : allow_count[11:8];
                hex1_value = rule_regen_mode ? regen_allow_count[7:4]   : allow_count[7:4];
                hex0_value = rule_regen_mode ? regen_allow_count[3:0]   : allow_count[3:0];
            end
            3'b011: begin
                hex3_value = rule_regen_mode ? regen_drop_count[15:12] : drop_count[15:12];
                hex2_value = rule_regen_mode ? regen_drop_count[11:8]  : drop_count[11:8];
                hex1_value = rule_regen_mode ? regen_drop_count[7:4]   : drop_count[7:4];
                hex0_value = rule_regen_mode ? regen_drop_count[3:0]   : drop_count[3:0];
            end
            3'b100: begin
                hex3_value = last_matched_rule_id;
                hex2_value = last_action_allow ? 4'hA : 4'hD;
                hex1_value = tx_error_b ? 4'hE : adapter_b_debug_state[3:0];
                hex0_value = {rx_fifo_overflow, tx_frame_ready, fifo_out_ready, rx_packet_seen_a};
            end
            3'b101: begin
                if (synthetic_tx_mode) begin
                    hex3_value = tx_test_count[15:12];
                    hex2_value = tx_test_count[11:8];
                    hex1_value = tx_test_count[7:4];
                    hex0_value = tx_test_count[3:0];
                end else begin
                    hex3_value = tx_count_b[15:12];
                    hex2_value = tx_count_b[11:8];
                    hex1_value = tx_count_b[7:4];
                    hex0_value = tx_count_b[3:0];
                end
            end
            3'b110: begin
                hex3_value = last_rx_size_bytes_a[15:12];
                hex2_value = last_rx_size_bytes_a[11:8];
                hex1_value = last_rx_size_bytes_a[7:4];
                hex0_value = last_rx_size_bytes_a[3:0];
            end
            3'b111: begin
                hex3_value = last_frame_len_bytes_a[15:12];
                hex2_value = last_frame_len_bytes_a[11:8];
                hex1_value = last_frame_len_bytes_a[7:4];
                hex0_value = last_frame_len_bytes_a[3:0];
            end
            default: begin
                hex_blank = 1'b1;
            end
        endcase
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            raw_rx_count <= 32'd0;
        end else if (rx_frame_valid && rx_frame_ready && rx_frame_eop) begin
            raw_rx_count <= raw_rx_count + 32'd1;
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            a_rx_capture_idx <= 5'd0;
            a_rx_capture[0]  <= 8'h00; a_rx_shadow[0]  <= 8'h00;
            a_rx_capture[1]  <= 8'h00; a_rx_shadow[1]  <= 8'h00;
            a_rx_capture[2]  <= 8'h00; a_rx_shadow[2]  <= 8'h00;
            a_rx_capture[3]  <= 8'h00; a_rx_shadow[3]  <= 8'h00;
            a_rx_capture[4]  <= 8'h00; a_rx_shadow[4]  <= 8'h00;
            a_rx_capture[5]  <= 8'h00; a_rx_shadow[5]  <= 8'h00;
            a_rx_capture[6]  <= 8'h00; a_rx_shadow[6]  <= 8'h00;
            a_rx_capture[7]  <= 8'h00; a_rx_shadow[7]  <= 8'h00;
            a_rx_capture[8]  <= 8'h00; a_rx_shadow[8]  <= 8'h00;
            a_rx_capture[9]  <= 8'h00; a_rx_shadow[9]  <= 8'h00;
            a_rx_capture[10] <= 8'h00; a_rx_shadow[10] <= 8'h00;
            a_rx_capture[11] <= 8'h00; a_rx_shadow[11] <= 8'h00;
            a_rx_capture[12] <= 8'h00; a_rx_shadow[12] <= 8'h00;
            a_rx_capture[13] <= 8'h00; a_rx_shadow[13] <= 8'h00;
            a_rx_capture[14] <= 8'h00; a_rx_shadow[14] <= 8'h00;
            a_rx_capture[15] <= 8'h00; a_rx_shadow[15] <= 8'h00;
        end else if (rx_frame_valid && rx_frame_ready) begin
            if (rx_frame_sop)
                a_rx_capture_idx <= 5'd0;
            if ((rx_frame_sop ? 5'd0 : a_rx_capture_idx) < 5'd16) begin
                a_rx_capture[rx_frame_sop ? 5'd0 : a_rx_capture_idx[3:0]] <= rx_frame_data;
                if (!rx_frame_sop)
                    a_rx_capture_idx <= a_rx_capture_idx + 5'd1;
                else
                    a_rx_capture_idx <= 5'd1;
            end
            if (rx_frame_eop) begin
                a_rx_shadow[0]  <= rx_frame_sop ? rx_frame_data : a_rx_capture[0];
                a_rx_shadow[1]  <= a_rx_capture[1];
                a_rx_shadow[2]  <= a_rx_capture[2];
                a_rx_shadow[3]  <= a_rx_capture[3];
                a_rx_shadow[4]  <= a_rx_capture[4];
                a_rx_shadow[5]  <= a_rx_capture[5];
                a_rx_shadow[6]  <= a_rx_capture[6];
                a_rx_shadow[7]  <= a_rx_capture[7];
                a_rx_shadow[8]  <= a_rx_capture[8];
                a_rx_shadow[9]  <= a_rx_capture[9];
                a_rx_shadow[10] <= a_rx_capture[10];
                a_rx_shadow[11] <= a_rx_capture[11];
                a_rx_shadow[12] <= a_rx_capture[12];
                a_rx_shadow[13] <= a_rx_capture[13];
                a_rx_shadow[14] <= a_rx_capture[14];
                a_rx_shadow[15] <= a_rx_capture[15];
            end
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            b_tx_capture_idx <= 5'd0;
            ever_b_eop_in    <= 1'b0;
            b_eop_in_count   <= 32'd0;
            b_tx_capture[0]  <= 8'h00; b_tx_shadow[0]  <= 8'h00;
            b_tx_capture[1]  <= 8'h00; b_tx_shadow[1]  <= 8'h00;
            b_tx_capture[2]  <= 8'h00; b_tx_shadow[2]  <= 8'h00;
            b_tx_capture[3]  <= 8'h00; b_tx_shadow[3]  <= 8'h00;
            b_tx_capture[4]  <= 8'h00; b_tx_shadow[4]  <= 8'h00;
            b_tx_capture[5]  <= 8'h00; b_tx_shadow[5]  <= 8'h00;
            b_tx_capture[6]  <= 8'h00; b_tx_shadow[6]  <= 8'h00;
            b_tx_capture[7]  <= 8'h00; b_tx_shadow[7]  <= 8'h00;
            b_tx_capture[8]  <= 8'h00; b_tx_shadow[8]  <= 8'h00;
            b_tx_capture[9]  <= 8'h00; b_tx_shadow[9]  <= 8'h00;
            b_tx_capture[10] <= 8'h00; b_tx_shadow[10] <= 8'h00;
            b_tx_capture[11] <= 8'h00; b_tx_shadow[11] <= 8'h00;
            b_tx_capture[12] <= 8'h00; b_tx_shadow[12] <= 8'h00;
            b_tx_capture[13] <= 8'h00; b_tx_shadow[13] <= 8'h00;
            b_tx_capture[14] <= 8'h00; b_tx_shadow[14] <= 8'h00;
            b_tx_capture[15] <= 8'h00; b_tx_shadow[15] <= 8'h00;
        end else if (tx_to_b_valid && tx_frame_ready) begin
            if (tx_to_b_sop)
                b_tx_capture_idx <= 5'd0;
            if ((tx_to_b_sop ? 5'd0 : b_tx_capture_idx) < 5'd16) begin
                b_tx_capture[tx_to_b_sop ? 5'd0 : b_tx_capture_idx[3:0]] <= tx_to_b_data;
                if (!tx_to_b_sop)
                    b_tx_capture_idx <= b_tx_capture_idx + 5'd1;
                else
                    b_tx_capture_idx <= 5'd1;
            end
            if (tx_to_b_eop) begin
                ever_b_eop_in  <= 1'b1;
                b_eop_in_count <= b_eop_in_count + 32'd1;
                b_tx_shadow[0]  <= tx_to_b_sop ? tx_to_b_data : b_tx_capture[0];
                b_tx_shadow[1]  <= b_tx_capture[1];
                b_tx_shadow[2]  <= b_tx_capture[2];
                b_tx_shadow[3]  <= b_tx_capture[3];
                b_tx_shadow[4]  <= b_tx_capture[4];
                b_tx_shadow[5]  <= b_tx_capture[5];
                b_tx_shadow[6]  <= b_tx_capture[6];
                b_tx_shadow[7]  <= b_tx_capture[7];
                b_tx_shadow[8]  <= b_tx_capture[8];
                b_tx_shadow[9]  <= b_tx_capture[9];
                b_tx_shadow[10] <= b_tx_capture[10];
                b_tx_shadow[11] <= b_tx_capture[11];
                b_tx_shadow[12] <= b_tx_capture[12];
                b_tx_shadow[13] <= b_tx_capture[13];
                b_tx_shadow[14] <= b_tx_capture[14];
                b_tx_shadow[15] <= b_tx_capture[15];
            end
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            ever_b_buf_write     <= 1'b0;
            ever_b_send_issued   <= 1'b0;
            ever_b_send_cleared  <= 1'b0;
            ever_b_send_timeout  <= 1'b0;
            ever_b_in_st_ready   <= 1'b0;
        end else begin
            if (b_buf_write_start_count != 32'd0) ever_b_buf_write    <= 1'b1;
            if (b_send_issued_count    != 32'd0) ever_b_send_issued  <= 1'b1;
            if (b_send_cleared_count   != 32'd0) ever_b_send_cleared <= 1'b1;
            if (b_send_timeout_count   != 32'd0) ever_b_send_timeout <= 1'b1;
            if (adapter_b_debug_state == 5'd6)   ever_b_in_st_ready  <= 1'b1;
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            regen_frames_seen        <= 32'd0;
            regen_last_eop_byte_idx  <= 16'd0;
            regen_max_byte_idx       <= 16'd0;
            rx_per_frame_byte_idx    <= 16'd0;
            rx_probe_byte_index      <= 16'd0;
            rx_probe_ethertype       <= 16'd0;
            rx_probe_ip_proto        <= 8'd0;
            rx_probe_dst_port        <= 16'd0;
        end else if (rx_frame_valid && rx_frame_ready) begin
            if (rx_frame_sop)
                rx_per_frame_byte_idx <= 16'd1;
            else
                rx_per_frame_byte_idx <= rx_per_frame_byte_idx + 16'd1;

            if (rx_frame_sop) begin
                rx_probe_byte_index <= 16'd0;
                rx_probe_ethertype  <= 16'd0;
                rx_probe_ip_proto   <= 8'd0;
                rx_probe_dst_port   <= 16'd0;
            end else begin
                rx_probe_byte_index <= rx_probe_byte_index + 16'd1;
            end

            case (rx_frame_sop ? 16'd0 : (rx_probe_byte_index + 16'd1))
                16'd12: rx_probe_ethertype[15:8] <= rx_frame_data;
                16'd13: rx_probe_ethertype[7:0]  <= rx_frame_data;
                16'd23: rx_probe_ip_proto         <= rx_frame_data;
                16'd36: rx_probe_dst_port[15:8]   <= rx_frame_data;
                16'd37: rx_probe_dst_port[7:0]    <= rx_frame_data;
                default: begin end
            endcase

            if (rx_frame_eop) begin
                regen_frames_seen       <= regen_frames_seen + 32'd1;
                regen_last_eop_byte_idx <= rx_frame_sop ? 16'd0 : rx_per_frame_byte_idx;
                if ((rx_frame_sop ? 16'd0 : rx_per_frame_byte_idx) > regen_max_byte_idx)
                    regen_max_byte_idx  <= rx_frame_sop ? 16'd0 : rx_per_frame_byte_idx;
            end
        end
    end

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            regen_allow_pending <= 1'b0;
            regen_byte_index    <= 16'd0;
            regen_ethertype     <= 16'd0;
            regen_ip_proto      <= 8'd0;
            regen_dst_port      <= 16'd0;
            regen_allow_count   <= 32'd0;
            regen_drop_count    <= 32'd0;
        end else if (!rule_regen_mode) begin
            regen_allow_pending <= 1'b0;
            regen_byte_index    <= 16'd0;
            regen_ethertype     <= 16'd0;
            regen_ip_proto      <= 8'd0;
            regen_dst_port      <= 16'd0;
        end else if (tx_test_valid && tx_frame_ready && tx_test_eop) begin
            regen_allow_pending <= 1'b0;
        end else if (rx_frame_valid && rx_frame_ready) begin
            if (rx_frame_sop) begin
                regen_byte_index <= 16'd0;
                regen_ethertype  <= 16'd0;
                regen_ip_proto   <= 8'd0;
                regen_dst_port   <= 16'd0;
            end else begin
                regen_byte_index <= regen_byte_index + 16'd1;
            end

            case (rx_frame_sop ? 16'd0 : (regen_byte_index + 16'd1))
                16'd12: regen_ethertype[15:8] <= rx_frame_data;
                16'd13: regen_ethertype[7:0]  <= rx_frame_data;
                16'd23: regen_ip_proto         <= rx_frame_data;
                16'd36: regen_dst_port[15:8]   <= rx_frame_data;
                16'd37: begin
                    regen_dst_port[7:0] <= rx_frame_data;
                    if ((regen_ethertype == 16'h0800) &&
                        (((regen_ip_proto == 8'h06) && ({regen_dst_port[15:8], rx_frame_data} == 16'd22)) ||
                         ((regen_ip_proto == 8'h11) && ({regen_dst_port[15:8], rx_frame_data} == 16'd80)))) begin
                        regen_allow_pending <= 1'b1;
                        regen_allow_count   <= regen_allow_count + 32'd1;
                    end else if ((regen_ethertype == 16'h0800) &&
                                 (regen_ip_proto == 8'h06) &&
                                 ({regen_dst_port[15:8], rx_frame_data} == 16'd23)) begin
                        regen_drop_count <= regen_drop_count + 32'd1;
                    end
                end
                default: begin end
            endcase
        end
    end

    function [7:0] tx_test_frame_byte;
        input [7:0] idx;
        begin
            case (idx)
                8'd0:  tx_test_frame_byte = 8'hFF;
                8'd1:  tx_test_frame_byte = 8'hFF;
                8'd2:  tx_test_frame_byte = 8'hFF;
                8'd3:  tx_test_frame_byte = 8'hFF;
                8'd4:  tx_test_frame_byte = 8'hFF;
                8'd5:  tx_test_frame_byte = 8'hFF;
                8'd6:  tx_test_frame_byte = 8'h00;
                8'd7:  tx_test_frame_byte = 8'h11;
                8'd8:  tx_test_frame_byte = 8'h22;
                8'd9:  tx_test_frame_byte = 8'h33;
                8'd10: tx_test_frame_byte = 8'h44;
                8'd11: tx_test_frame_byte = 8'h55;
                8'd12: tx_test_frame_byte = 8'h08;
                8'd13: tx_test_frame_byte = 8'h00;
                8'd14: tx_test_frame_byte = 8'h45;
                8'd15: tx_test_frame_byte = 8'h00;
                8'd16: tx_test_frame_byte = 8'h00;
                8'd17: tx_test_frame_byte = 8'h42;
                8'd18: tx_test_frame_byte = 8'h12;
                8'd19: tx_test_frame_byte = 8'h34;
                8'd20: tx_test_frame_byte = 8'h00;
                8'd21: tx_test_frame_byte = 8'h00;
                8'd22: tx_test_frame_byte = 8'h40;
                8'd23: tx_test_frame_byte = 8'h06;
                8'd24: tx_test_frame_byte = 8'h00;
                8'd25: tx_test_frame_byte = 8'h00;
                8'd26: tx_test_frame_byte = 8'h0A;
                8'd27: tx_test_frame_byte = 8'h01;
                8'd28: tx_test_frame_byte = 8'h02;
                8'd29: tx_test_frame_byte = 8'h03;
                8'd30: tx_test_frame_byte = 8'hC0;
                8'd31: tx_test_frame_byte = 8'hA8;
                8'd32: tx_test_frame_byte = 8'h01;
                8'd33: tx_test_frame_byte = 8'h63;
                8'd34: tx_test_frame_byte = 8'h08;
                8'd35: tx_test_frame_byte = 8'hAE;
                8'd36: tx_test_frame_byte = 8'h00;
                8'd37: tx_test_frame_byte = 8'h16;
                8'd38: tx_test_frame_byte = 8'h00;
                8'd39: tx_test_frame_byte = 8'h00;
                8'd40: tx_test_frame_byte = 8'h00;
                8'd41: tx_test_frame_byte = 8'h01;
                8'd42: tx_test_frame_byte = 8'h00;
                8'd43: tx_test_frame_byte = 8'h00;
                8'd44: tx_test_frame_byte = 8'h00;
                8'd45: tx_test_frame_byte = 8'h00;
                8'd46: tx_test_frame_byte = 8'h50;
                8'd47: tx_test_frame_byte = 8'h02;
                8'd48: tx_test_frame_byte = 8'h20;
                8'd49: tx_test_frame_byte = 8'h00;
                8'd50: tx_test_frame_byte = 8'h00;
                8'd51: tx_test_frame_byte = 8'h00;
                8'd52: tx_test_frame_byte = "F";
                8'd53: tx_test_frame_byte = "W";
                8'd54: tx_test_frame_byte = "-";
                8'd55: tx_test_frame_byte = "D";
                8'd56: tx_test_frame_byte = "E";
                8'd57: tx_test_frame_byte = "M";
                8'd58: tx_test_frame_byte = "O";
                8'd59: tx_test_frame_byte = "-";
                8'd60: tx_test_frame_byte = "A";
                8'd61: tx_test_frame_byte = "L";
                8'd62: tx_test_frame_byte = "L";
                8'd63: tx_test_frame_byte = "O";
                8'd64: tx_test_frame_byte = "W";
                8'd65: tx_test_frame_byte = "-";
                8'd66: tx_test_frame_byte = "S";
                8'd67: tx_test_frame_byte = "S";
                8'd68: tx_test_frame_byte = "H";
                8'd69: tx_test_frame_byte = " ";
                8'd70: tx_test_frame_byte = "s";
                8'd71: tx_test_frame_byte = "e";
                8'd72: tx_test_frame_byte = "q";
                8'd73: tx_test_frame_byte = "=";
                8'd74: tx_test_frame_byte = "9";
                8'd75: tx_test_frame_byte = "0";
                8'd76: tx_test_frame_byte = "0";
                8'd77: tx_test_frame_byte = "0";
                default: tx_test_frame_byte = 8'h00;
            endcase
        end
    endfunction

    always @(posedge CLOCK_50 or negedge rst_n) begin
        if (!rst_n) begin
            tx_test_valid    <= 1'b0;
            tx_test_data     <= 8'd0;
            tx_test_sop      <= 1'b0;
            tx_test_eop      <= 1'b0;
            tx_test_index    <= 8'd0;
            tx_test_wait_ctr <= 32'd0;
            tx_test_count    <= 32'd0;
        end else if (!synthetic_tx_mode) begin
            tx_test_valid    <= 1'b0;
            tx_test_sop      <= 1'b0;
            tx_test_eop      <= 1'b0;
            tx_test_index    <= 8'd0;
            tx_test_wait_ctr <= 32'd0;
        end else begin
            tx_test_sop <= 1'b0;
            tx_test_eop <= 1'b0;

            if (tx_test_valid) begin
                if (tx_frame_ready) begin
                    if (tx_test_index == 8'd77) begin
                        tx_test_valid <= 1'b0;
                        tx_test_index <= 8'd0;
                        tx_test_count <= tx_test_count + 32'd1;
                    end else begin
                        tx_test_index <= tx_test_index + 8'd1;
                        tx_test_data  <= tx_test_frame_byte(tx_test_index + 8'd1);
                        tx_test_sop   <= 1'b0;
                        tx_test_eop   <= (tx_test_index == 8'd76);
                    end
                end
            end else if (rule_regen_mode && regen_allow_pending && init_done_b) begin
                tx_test_valid    <= 1'b1;
                tx_test_data     <= tx_test_frame_byte(8'd0);
                tx_test_sop      <= 1'b1;
                tx_test_eop      <= 1'b0;
                tx_test_index    <= 8'd0;
                tx_test_wait_ctr <= 32'd0;
            end else if (tx_test_mode && (tx_test_wait_ctr == 32'd25_000_000)) begin
                tx_test_wait_ctr <= 32'd0;
                tx_test_valid    <= init_done_b;
                tx_test_data     <= tx_test_frame_byte(8'd0);
                tx_test_sop      <= init_done_b;
                tx_test_eop      <= 1'b0;
                tx_test_index    <= 8'd0;
            end else if (tx_test_mode) begin
                tx_test_wait_ctr <= tx_test_wait_ctr + 32'd1;
            end else begin
                tx_test_wait_ctr <= 32'd0;
            end
        end
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
        .RX_POLL_WAIT_CYCLES(5_000),
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
        .rx_commit_count(rx_commit_count_a),
        .rx_stream_byte_count(rx_stream_byte_count_a),
        .last_rx_size_bytes(last_rx_size_bytes_a),
        .last_frame_len_bytes(last_frame_len_bytes_a),
        .debug_state(adapter_a_debug_state)
    );

    frame_rx_fifo #(
        .PACKET_DEPTH(8),
        .MAX_PKT_BYTES(2048)
    ) u_ingress_fifo (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .in_valid((rx_drain_debug || forward_bypass_mode || rule_regen_mode) ? 1'b0 : rx_frame_valid),
        .in_data(rx_frame_data),
        .in_sop(rx_frame_sop),
        .in_eop(rx_frame_eop),
        .in_src_port(rx_frame_src_port),
        .in_ready(rx_fifo_in_ready),
        .out_valid(core_frame_valid),
        .out_data(core_frame_data),
        .out_sop(core_frame_sop),
        .out_eop(core_frame_eop),
        .out_src_port(core_frame_src_port),
        .out_ready(fifo_out_ready),
        .overflow_error(rx_fifo_overflow)
    );

    firewall_forwarder #(
        .MAX_PKT_BYTES(2048)
    ) u_firewall_forwarder (
        .clk(CLOCK_50),
        .rst_n(rst_n),
        .in_valid(forward_bypass_mode ? 1'b0 : core_frame_valid),
        .in_data(core_frame_data),
        .in_sop(core_frame_sop),
        .in_eop(core_frame_eop),
        .in_src_port(core_frame_src_port),
        .in_ready(core_frame_ready),
        .out_valid(tx_frame_valid),
        .out_data(tx_frame_data),
        .out_sop(tx_frame_sop),
        .out_eop(tx_frame_eop),
        .out_src_port(tx_frame_src_port),
        .out_ready(forwarder_out_ready),
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
        .frame_valid(tx_to_b_valid),
        .frame_data(tx_to_b_data),
        .frame_sop(tx_to_b_sop),
        .frame_eop(tx_to_b_eop),
        .frame_ready(tx_frame_ready),
        .init_busy(),
        .init_done(init_done_b),
        .init_error(init_error_b),
        .tx_count(tx_count_b),
        .tx_error(tx_error_b),
        .debug_state(adapter_b_debug_state),
        .last_pkt_len_dbg(b_last_pkt_len),
        .pkt_available_dbg(b_pkt_available),
        .buf_write_start_count(b_buf_write_start_count),
        .send_issued_count(b_send_issued_count),
        .send_cleared_count(b_send_cleared_count),
        .send_timeout_count(b_send_timeout_count)
    );
endmodule
