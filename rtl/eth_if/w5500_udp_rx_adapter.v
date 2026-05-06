`timescale 1ns/1ps

module w5500_udp_rx_adapter #(
    parameter STARTUP_WAIT_CYCLES = 16,
    parameter RESET_ASSERT_CYCLES = 16,
    parameter RESET_RELEASE_CYCLES = 32,
    parameter RX_POLL_WAIT_CYCLES = 32,
    parameter SPI_CLK_DIV = 4,
    parameter MAX_FRAME_BYTES = 512,
    parameter PHY_POLL_INTERVAL_POLLS = 256
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_init,

    output reg         w5500_reset_n,
    input  wire        w5500_int_n,
    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    output reg         init_busy,
    output reg         init_done,
    output reg         init_error,
    output reg         rx_packet_seen,

    output reg         frame_valid,
    output reg [7:0]   frame_data,
    output reg         frame_sop,
    output reg         frame_eop,
    output reg [0:0]   frame_src_port,
    input  wire        frame_ready,

    output reg [31:0]  rx_commit_count,
    output reg [31:0]  rx_stream_byte_count,
    output reg [15:0]  last_rx_size_bytes,
    output reg [15:0]  last_frame_len_bytes,
    output reg [7:0]   phy_cfgr_value,
    output reg [31:0]  phy_read_count,
    output reg [7:0]   socket_mode_value,
    output reg [7:0]   socket_status_value,
    output reg [47:0]  shar_value,
    output reg [31:0]  sipr_value,
    output reg [3:0]   debug_state
);
    localparam ST_IDLE         = 4'd0;
    localparam ST_RESET        = 4'd1;
    localparam ST_VERSION      = 4'd2;
    localparam ST_COMMON_CFG   = 4'd3;
    localparam ST_SOCKET_CFG   = 4'd4;
    localparam ST_SOCKET_OPEN  = 4'd5;
    localparam ST_RX_POLL      = 4'd6;
    localparam ST_READ_RD_PTR  = 4'd7;
    localparam ST_READ_UDP_HDR = 4'd8;
    localparam ST_STREAM_FRAME = 4'd9;
    localparam ST_COMMIT_RX    = 4'd10;
    localparam ST_WAIT_RECV    = 4'd11;
    localparam ST_READ_PHY     = 4'd12;
    localparam ST_WAIT_LINK    = 4'd13;
    localparam ST_ERROR        = 4'd15;

    localparam [15:0] COMMON_MR         = 16'h0000;
    localparam [15:0] COMMON_GAR0       = 16'h0001;
    localparam [15:0] COMMON_GAR1       = 16'h0002;
    localparam [15:0] COMMON_GAR2       = 16'h0003;
    localparam [15:0] COMMON_GAR3       = 16'h0004;
    localparam [15:0] COMMON_SUBR0      = 16'h0005;
    localparam [15:0] COMMON_SUBR1      = 16'h0006;
    localparam [15:0] COMMON_SUBR2      = 16'h0007;
    localparam [15:0] COMMON_SUBR3      = 16'h0008;
    localparam [15:0] COMMON_SHAR0      = 16'h0009;
    localparam [15:0] COMMON_SHAR1      = 16'h000A;
    localparam [15:0] COMMON_SHAR2      = 16'h000B;
    localparam [15:0] COMMON_SHAR3      = 16'h000C;
    localparam [15:0] COMMON_SHAR4      = 16'h000D;
    localparam [15:0] COMMON_SHAR5      = 16'h000E;
    localparam [15:0] COMMON_SIPR0      = 16'h000F;
    localparam [15:0] COMMON_SIPR1      = 16'h0010;
    localparam [15:0] COMMON_SIPR2      = 16'h0011;
    localparam [15:0] COMMON_SIPR3      = 16'h0012;
    localparam [15:0] COMMON_PHYCFGR    = 16'h002E;
    localparam [15:0] COMMON_VERSIONR   = 16'h0039;

    localparam [15:0] S0_MR             = 16'h0000;
    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_IR             = 16'h0002;
    localparam [15:0] S0_SR             = 16'h0003;
    localparam [15:0] S0_PORT0          = 16'h0004;
    localparam [15:0] S0_PORT1          = 16'h0005;
    localparam [15:0] S0_RXBUF_SIZE     = 16'h001E;
    localparam [15:0] S0_TXBUF_SIZE     = 16'h001F;
    localparam [15:0] S0_RX_RSR_MSB     = 16'h0026;
    localparam [15:0] S0_RX_RSR_LSB     = 16'h0027;
    localparam [15:0] S0_RX_RD_MSB      = 16'h0028;
    localparam [15:0] S0_RX_RD_LSB      = 16'h0029;

    localparam [7:0] CTRL_COMMON_READ   = 8'h00;
    localparam [7:0] CTRL_COMMON_WRITE  = 8'h04;
    localparam [7:0] CTRL_S0_REG_READ   = 8'h08;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h0C;
    localparam [7:0] CTRL_S0_RXBUF_READ = 8'h18;

    localparam [7:0] W5500_VERSION      = 8'h04;
    localparam [7:0] S0_MR_UDP          = 8'h02;
    localparam [7:0] S0_CR_OPEN         = 8'h01;
    localparam [7:0] S0_CR_RECV         = 8'h40;
    localparam [7:0] S0_STATUS_UDP      = 8'h22;
    localparam [7:0] SOCKET_RXBUF_4KB   = 8'h04;
    localparam [7:0] SOCKET_TXBUF_0KB   = 8'h00;

    localparam [1:0]  SOCKET_LAST        = 2'd2;
    localparam [15:0] LOCAL_PORT0       = 16'd80;
    localparam [15:0] LOCAL_PORT1       = 16'd5001;
    localparam [15:0] LOCAL_PORT2       = 16'd5002;
    localparam [31:0] LOCAL_IP          = 32'hC0A80101;
    localparam [15:0] UDP_RECORD_BYTES  = 16'd8;
    localparam [15:0] SYNTH_HDR_BYTES   = 16'd42;

    reg [3:0]  state;
    reg [4:0]  state_step;
    reg [31:0] wait_ctr;
    reg [15:0] rx_poll_wait_ctr;
    reg [15:0] phy_poll_idle_count;

    reg        spi_start;
    reg        spi_hold_cs;
    reg [7:0]  spi_tx_data;
    wire [7:0] spi_rx_data;
    wire       spi_busy;
    wire       spi_done;

    reg        seq_active;
    reg        seq_done;
    reg [15:0] seq_count;
    reg [15:0] seq_index;
    reg [7:0]  seq_tx [0:3];
    reg [7:0]  seq_rx [0:3];

    reg [15:0] rx_size_bytes;
    reg [15:0] rx_read_ptr;
    reg [15:0] next_rx_read_ptr;
    reg [15:0] frame_index;
    reg [31:0] peer_ip;
    reg [15:0] peer_port;
    reg [15:0] udp_payload_len;
    reg [1:0]  poll_socket;
    reg [1:0]  active_socket;

    spi_master #(
        .CLK_DIV(SPI_CLK_DIV),
        .CPOL(0),
        .CPHA(0)
    ) u_spi_master (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .hold_cs(spi_hold_cs),
        .tx_data(spi_tx_data),
        .rx_data(spi_rx_data),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .cs_n(spi_cs_n)
    );

    function [1:0] next_socket;
        input [1:0] socket_i;
        begin
            next_socket = (socket_i == SOCKET_LAST) ? 2'd0 : (socket_i + 2'd1);
        end
    endfunction

    function [7:0] socket_reg_read_ctrl;
        input [1:0] socket_i;
        begin
            socket_reg_read_ctrl = 8'h08 + {socket_i, 5'b00000};
        end
    endfunction

    function [7:0] socket_reg_write_ctrl;
        input [1:0] socket_i;
        begin
            socket_reg_write_ctrl = 8'h0C + {socket_i, 5'b00000};
        end
    endfunction

    function [7:0] socket_rxbuf_read_ctrl;
        input [1:0] socket_i;
        begin
            socket_rxbuf_read_ctrl = 8'h18 + {socket_i, 5'b00000};
        end
    endfunction

    function [15:0] local_port_for_socket;
        input [1:0] socket_i;
        begin
            case (socket_i)
                2'd0: local_port_for_socket = LOCAL_PORT0;
                2'd1: local_port_for_socket = LOCAL_PORT1;
                default: local_port_for_socket = LOCAL_PORT2;
            endcase
        end
    endfunction

    function [15:0] ipv4_header_checksum;
        input [15:0] payload_len_i;
        input [31:0] src_ip_i;
        reg [31:0] sum;
        reg [31:0] folded;
        begin
            sum = 32'h00004500 +
                  {16'd0, (16'd28 + payload_len_i)} +
                  32'h00004011 +
                  {16'd0, src_ip_i[31:16]} +
                  {16'd0, src_ip_i[15:0]} +
                  {16'd0, LOCAL_IP[31:16]} +
                  {16'd0, LOCAL_IP[15:0]};
            folded = {16'd0, sum[15:0]} + {16'd0, sum[31:16]};
            folded = {16'd0, folded[15:0]} + {16'd0, folded[31:16]};
            ipv4_header_checksum = ~folded[15:0];
        end
    endfunction

    function [7:0] synth_header_byte;
        input [15:0] idx;
        input [15:0] payload_len_i;
        input [31:0] src_ip_i;
        input [15:0] src_port_i;
        input [15:0] dst_port_i;
        reg [15:0] ip_total_len;
        reg [15:0] udp_len;
        reg [15:0] ip_check;
        begin
            ip_total_len = 16'd28 + payload_len_i;
            udp_len      = 16'd8 + payload_len_i;
            ip_check     = ipv4_header_checksum(payload_len_i, src_ip_i);
            case (idx)
                16'd0, 16'd1, 16'd2, 16'd3, 16'd4, 16'd5:
                    synth_header_byte = 8'hFF;
                16'd6:  synth_header_byte = 8'h00;
                16'd7:  synth_header_byte = 8'h11;
                16'd8:  synth_header_byte = 8'h22;
                16'd9:  synth_header_byte = 8'h33;
                16'd10: synth_header_byte = 8'h44;
                16'd11: synth_header_byte = 8'h55;
                16'd12: synth_header_byte = 8'h08;
                16'd13: synth_header_byte = 8'h00;
                16'd14: synth_header_byte = 8'h45;
                16'd15: synth_header_byte = 8'h00;
                16'd16: synth_header_byte = ip_total_len[15:8];
                16'd17: synth_header_byte = ip_total_len[7:0];
                16'd18, 16'd19, 16'd20, 16'd21:
                    synth_header_byte = 8'h00;
                16'd22: synth_header_byte = 8'h40;
                16'd23: synth_header_byte = 8'h11;
                16'd24: synth_header_byte = ip_check[15:8];
                16'd25: synth_header_byte = ip_check[7:0];
                16'd26: synth_header_byte = src_ip_i[31:24];
                16'd27: synth_header_byte = src_ip_i[23:16];
                16'd28: synth_header_byte = src_ip_i[15:8];
                16'd29: synth_header_byte = src_ip_i[7:0];
                16'd30: synth_header_byte = LOCAL_IP[31:24];
                16'd31: synth_header_byte = LOCAL_IP[23:16];
                16'd32: synth_header_byte = LOCAL_IP[15:8];
                16'd33: synth_header_byte = LOCAL_IP[7:0];
                16'd34: synth_header_byte = src_port_i[15:8];
                16'd35: synth_header_byte = src_port_i[7:0];
                16'd36: synth_header_byte = dst_port_i[15:8];
                16'd37: synth_header_byte = dst_port_i[7:0];
                16'd38: synth_header_byte = udp_len[15:8];
                16'd39: synth_header_byte = udp_len[7:0];
                16'd40, 16'd41:
                    synth_header_byte = 8'h00;
                default:
                    synth_header_byte = 8'h00;
            endcase
        end
    endfunction

    task start_spi_read;
        input [15:0] addr;
        input [7:0]  ctrl;
        begin
            seq_tx[0]   <= addr[15:8];
            seq_tx[1]   <= addr[7:0];
            seq_tx[2]   <= ctrl;
            seq_tx[3]   <= 8'h00;
            seq_count   <= 16'd4;
            seq_index   <= 16'd0;
            seq_active  <= 1'b1;
            spi_tx_data <= addr[15:8];
            spi_hold_cs <= 1'b1;
            spi_start   <= 1'b1;
        end
    endtask

    task start_spi_write;
        input [15:0] addr;
        input [7:0]  ctrl;
        input [7:0]  data;
        begin
            seq_tx[0]   <= addr[15:8];
            seq_tx[1]   <= addr[7:0];
            seq_tx[2]   <= ctrl;
            seq_tx[3]   <= data;
            seq_count   <= 16'd4;
            seq_index   <= 16'd0;
            seq_active  <= 1'b1;
            spi_tx_data <= addr[15:8];
            spi_hold_cs <= 1'b1;
            spi_start   <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            state_step       <= 5'd0;
            wait_ctr         <= 32'd0;
            rx_poll_wait_ctr <= 16'd0;
            phy_poll_idle_count <= 16'd0;
            w5500_reset_n    <= 1'b1;
            spi_start        <= 1'b0;
            spi_hold_cs      <= 1'b0;
            spi_tx_data      <= 8'd0;
            seq_active       <= 1'b0;
            seq_done         <= 1'b0;
            seq_count        <= 16'd0;
            seq_index        <= 16'd0;
            seq_rx[0]        <= 8'd0;
            seq_rx[1]        <= 8'd0;
            seq_rx[2]        <= 8'd0;
            seq_rx[3]        <= 8'd0;
            init_busy        <= 1'b0;
            init_done        <= 1'b0;
            init_error       <= 1'b0;
            rx_packet_seen   <= 1'b0;
            frame_valid      <= 1'b0;
            frame_data       <= 8'd0;
            frame_sop        <= 1'b0;
            frame_eop        <= 1'b0;
            frame_src_port   <= 1'b0;
            rx_commit_count  <= 32'd0;
            rx_stream_byte_count <= 32'd0;
            last_rx_size_bytes <= 16'd0;
            last_frame_len_bytes <= 16'd0;
            phy_cfgr_value   <= 8'd0;
            phy_read_count   <= 32'd0;
            socket_mode_value <= 8'd0;
            socket_status_value <= 8'd0;
            shar_value       <= 48'd0;
            sipr_value       <= 32'd0;
            debug_state      <= ST_IDLE;
            rx_size_bytes    <= 16'd0;
            rx_read_ptr      <= 16'd0;
            next_rx_read_ptr <= 16'd0;
            frame_index      <= 16'd0;
            peer_ip          <= 32'd0;
            peer_port        <= 16'd0;
            udp_payload_len  <= 16'd0;
            poll_socket      <= 2'd0;
            active_socket    <= 2'd0;
        end else begin
            spi_start   <= 1'b0;
            seq_done    <= 1'b0;
            frame_valid <= 1'b0;
            frame_sop   <= 1'b0;
            frame_eop   <= 1'b0;
            debug_state <= state;

            if (seq_active && spi_done) begin
                if (seq_index < 16'd4)
                    seq_rx[seq_index[1:0]] <= spi_rx_data;

                if (seq_index == (seq_count - 16'd1)) begin
                    seq_active <= 1'b0;
                    seq_done   <= 1'b1;
                end else begin
                    seq_index <= seq_index + 16'd1;
                    spi_tx_data <= seq_tx[seq_index[1:0] + 2'd1];
                    spi_hold_cs <= ((seq_index + 16'd1) != (seq_count - 16'd1));
                    spi_start   <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    init_busy      <= 1'b0;
                    init_done      <= 1'b0;
                    init_error     <= 1'b0;
                    rx_packet_seen <= 1'b0;
                    frame_src_port <= 1'b0;
                    w5500_reset_n  <= 1'b1;
                    state_step     <= 5'd0;
                    wait_ctr       <= 32'd0;
                    poll_socket    <= 2'd0;
                    active_socket  <= 2'd0;
                    if (start_init) begin
                        init_busy     <= 1'b1;
                        w5500_reset_n <= 1'b0;
                        wait_ctr      <= 32'd0;
                        state         <= ST_RESET;
                    end
                end

                ST_RESET: begin
                    if (!w5500_reset_n) begin
                        if (wait_ctr == (RESET_ASSERT_CYCLES - 1)) begin
                            w5500_reset_n <= 1'b1;
                            wait_ctr      <= 32'd0;
                        end else begin
                            wait_ctr <= wait_ctr + 32'd1;
                        end
                    end else begin
                        if (wait_ctr == (RESET_RELEASE_CYCLES + STARTUP_WAIT_CYCLES - 1)) begin
                            wait_ctr   <= 32'd0;
                            state_step <= 5'd0;
                            state      <= ST_VERSION;
                        end else begin
                            wait_ctr <= wait_ctr + 32'd1;
                        end
                    end
                end

                ST_VERSION: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(COMMON_VERSIONR, CTRL_COMMON_READ);
                    else if (seq_done) begin
                        if (seq_rx[3] == W5500_VERSION) begin
                            state      <= ST_COMMON_CFG;
                            state_step <= 5'd0;
                        end else begin
                            init_busy  <= 1'b0;
                            init_error <= 1'b1;
                            state      <= ST_ERROR;
                        end
                    end
                end

                ST_COMMON_CFG: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            5'd0:  start_spi_write(COMMON_MR,    CTRL_COMMON_WRITE, 8'h00);
                            5'd1:  start_spi_write(COMMON_GAR0,  CTRL_COMMON_WRITE, 8'hC0);
                            5'd2:  start_spi_write(COMMON_GAR1,  CTRL_COMMON_WRITE, 8'hA8);
                            5'd3:  start_spi_write(COMMON_GAR2,  CTRL_COMMON_WRITE, 8'h01);
                            5'd4:  start_spi_write(COMMON_GAR3,  CTRL_COMMON_WRITE, 8'h0A);
                            5'd5:  start_spi_write(COMMON_SUBR0, CTRL_COMMON_WRITE, 8'hFF);
                            5'd6:  start_spi_write(COMMON_SUBR1, CTRL_COMMON_WRITE, 8'hFF);
                            5'd7:  start_spi_write(COMMON_SUBR2, CTRL_COMMON_WRITE, 8'hFF);
                            5'd8:  start_spi_write(COMMON_SUBR3, CTRL_COMMON_WRITE, 8'h00);
                            5'd9:  start_spi_write(COMMON_SHAR0, CTRL_COMMON_WRITE, 8'h02);
                            5'd10: start_spi_write(COMMON_SHAR1, CTRL_COMMON_WRITE, 8'h00);
                            5'd11: start_spi_write(COMMON_SHAR2, CTRL_COMMON_WRITE, 8'h00);
                            5'd12: start_spi_write(COMMON_SHAR3, CTRL_COMMON_WRITE, 8'hDE);
                            5'd13: start_spi_write(COMMON_SHAR4, CTRL_COMMON_WRITE, 8'hAD);
                            5'd14: start_spi_write(COMMON_SHAR5, CTRL_COMMON_WRITE, 8'h0A);
                            5'd15: start_spi_write(COMMON_SIPR0, CTRL_COMMON_WRITE, 8'hC0);
                            5'd16: start_spi_write(COMMON_SIPR1, CTRL_COMMON_WRITE, 8'hA8);
                            5'd17: start_spi_write(COMMON_SIPR2, CTRL_COMMON_WRITE, 8'h01);
                            5'd18: start_spi_write(COMMON_SIPR3, CTRL_COMMON_WRITE, 8'h01);
                            default: begin
                                state      <= ST_SOCKET_CFG;
                                state_step <= 5'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 5'd18) begin
                            state      <= ST_SOCKET_CFG;
                            state_step <= 5'd0;
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_SOCKET_CFG: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            5'd0:  start_spi_write(S0_RXBUF_SIZE, socket_reg_write_ctrl(2'd0), SOCKET_RXBUF_4KB);
                            5'd1:  start_spi_write(S0_TXBUF_SIZE, socket_reg_write_ctrl(2'd0), SOCKET_TXBUF_0KB);
                            5'd2:  start_spi_write(S0_MR,         socket_reg_write_ctrl(2'd0), S0_MR_UDP);
                            5'd3:  start_spi_write(S0_PORT0,      socket_reg_write_ctrl(2'd0), LOCAL_PORT0[15:8]);
                            5'd4:  start_spi_write(S0_PORT1,      socket_reg_write_ctrl(2'd0), LOCAL_PORT0[7:0]);
                            5'd5:  start_spi_write(S0_RXBUF_SIZE, socket_reg_write_ctrl(2'd1), SOCKET_RXBUF_4KB);
                            5'd6:  start_spi_write(S0_TXBUF_SIZE, socket_reg_write_ctrl(2'd1), SOCKET_TXBUF_0KB);
                            5'd7:  start_spi_write(S0_MR,         socket_reg_write_ctrl(2'd1), S0_MR_UDP);
                            5'd8:  start_spi_write(S0_PORT0,      socket_reg_write_ctrl(2'd1), LOCAL_PORT1[15:8]);
                            5'd9:  start_spi_write(S0_PORT1,      socket_reg_write_ctrl(2'd1), LOCAL_PORT1[7:0]);
                            5'd10: start_spi_write(S0_RXBUF_SIZE, socket_reg_write_ctrl(2'd2), SOCKET_RXBUF_4KB);
                            5'd11: start_spi_write(S0_TXBUF_SIZE, socket_reg_write_ctrl(2'd2), SOCKET_TXBUF_0KB);
                            5'd12: start_spi_write(S0_MR,         socket_reg_write_ctrl(2'd2), S0_MR_UDP);
                            5'd13: start_spi_write(S0_PORT0,      socket_reg_write_ctrl(2'd2), LOCAL_PORT2[15:8]);
                            5'd14: start_spi_write(S0_PORT1,      socket_reg_write_ctrl(2'd2), LOCAL_PORT2[7:0]);
                            default: begin
                                state      <= ST_WAIT_LINK;
                                state_step <= 5'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 5'd14) begin
                            state      <= ST_WAIT_LINK;
                            state_step <= 5'd0;
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_WAIT_LINK: begin
                    init_busy <= 1'b1;
                    if (rx_poll_wait_ctr != RX_POLL_WAIT_CYCLES) begin
                        rx_poll_wait_ctr <= rx_poll_wait_ctr + 16'd1;
                    end else if (!seq_active && !seq_done) begin
                        start_spi_read(COMMON_PHYCFGR, CTRL_COMMON_READ);
                    end else if (seq_done) begin
                        phy_cfgr_value     <= seq_rx[3];
                        phy_read_count     <= phy_read_count + 32'd1;
                        rx_poll_wait_ctr   <= 16'd0;
                        if (seq_rx[3][0]) begin
                            state      <= ST_SOCKET_OPEN;
                            state_step <= 5'd0;
                        end
                    end
                end

                ST_SOCKET_OPEN: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            5'd0: start_spi_write(S0_CR, socket_reg_write_ctrl(2'd0), S0_CR_OPEN);
                            5'd1: start_spi_read(S0_SR, socket_reg_read_ctrl(2'd0));
                            5'd2: start_spi_write(S0_CR, socket_reg_write_ctrl(2'd1), S0_CR_OPEN);
                            5'd3: start_spi_read(S0_SR, socket_reg_read_ctrl(2'd1));
                            5'd4: start_spi_write(S0_CR, socket_reg_write_ctrl(2'd2), S0_CR_OPEN);
                            5'd5: start_spi_read(S0_SR, socket_reg_read_ctrl(2'd2));
                            default: begin
                                init_busy       <= 1'b0;
                                init_done       <= 1'b1;
                                rx_poll_wait_ctr<= 16'd0;
                                poll_socket     <= 2'd0;
                                state           <= ST_READ_PHY;
                                state_step      <= 5'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if ((state_step == 5'd1) || (state_step == 5'd3) || (state_step == 5'd5)) begin
                            socket_status_value <= seq_rx[3];
                            if (seq_rx[3] == S0_STATUS_UDP) begin
                                if (state_step == 5'd5) begin
                                    init_busy       <= 1'b0;
                                    init_done       <= 1'b1;
                                    rx_poll_wait_ctr<= 16'd0;
                                    poll_socket     <= 2'd0;
                                    state           <= ST_READ_PHY;
                                    state_step      <= 5'd0;
                                end else begin
                                    state_step <= state_step + 5'd1;
                                end
                            end else begin
                                init_busy  <= 1'b0;
                                init_error <= 1'b1;
                                state      <= ST_ERROR;
                            end
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_READ_PHY: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            5'd0:  start_spi_read(COMMON_PHYCFGR, CTRL_COMMON_READ);
                            5'd1:  start_spi_read(S0_MR, socket_reg_read_ctrl(2'd0));
                            5'd2:  start_spi_read(S0_SR, socket_reg_read_ctrl(2'd0));
                            5'd3:  start_spi_read(S0_SR, socket_reg_read_ctrl(2'd1));
                            5'd4:  start_spi_read(S0_SR, socket_reg_read_ctrl(2'd2));
                            5'd5:  start_spi_read(COMMON_SHAR0, CTRL_COMMON_READ);
                            5'd6:  start_spi_read(COMMON_SHAR1, CTRL_COMMON_READ);
                            5'd7:  start_spi_read(COMMON_SHAR2, CTRL_COMMON_READ);
                            5'd8:  start_spi_read(COMMON_SHAR3, CTRL_COMMON_READ);
                            5'd9:  start_spi_read(COMMON_SHAR4, CTRL_COMMON_READ);
                            5'd10: start_spi_read(COMMON_SHAR5, CTRL_COMMON_READ);
                            5'd11: start_spi_read(COMMON_SIPR0, CTRL_COMMON_READ);
                            5'd12: start_spi_read(COMMON_SIPR1, CTRL_COMMON_READ);
                            5'd13: start_spi_read(COMMON_SIPR2, CTRL_COMMON_READ);
                            5'd14: start_spi_read(COMMON_SIPR3, CTRL_COMMON_READ);
                            default: begin
                                rx_poll_wait_ctr <= 16'd0;
                                state            <= ST_RX_POLL;
                                state_step       <= 5'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        case (state_step)
                            5'd0:  phy_cfgr_value    <= seq_rx[3];
                            5'd1:  socket_mode_value <= seq_rx[3];
                            5'd2:  socket_status_value <= seq_rx[3];
                            5'd3:  begin end
                            5'd4:  begin end
                            5'd5:  shar_value[47:40] <= seq_rx[3];
                            5'd6:  shar_value[39:32] <= seq_rx[3];
                            5'd7:  shar_value[31:24] <= seq_rx[3];
                            5'd8:  shar_value[23:16] <= seq_rx[3];
                            5'd9:  shar_value[15:8]  <= seq_rx[3];
                            5'd10: shar_value[7:0]   <= seq_rx[3];
                            5'd11: sipr_value[31:24] <= seq_rx[3];
                            5'd12: sipr_value[23:16] <= seq_rx[3];
                            5'd13: sipr_value[15:8]  <= seq_rx[3];
                            5'd14: sipr_value[7:0]   <= seq_rx[3];
                        endcase

                        if (state_step == 5'd14) begin
                            phy_read_count   <= phy_read_count + 32'd1;
                            rx_poll_wait_ctr <= 16'd0;
                            state            <= ST_RX_POLL;
                            state_step       <= 5'd0;
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_RX_POLL: begin
                    init_done <= 1'b1;
                    if (rx_poll_wait_ctr != RX_POLL_WAIT_CYCLES && w5500_int_n) begin
                        rx_poll_wait_ctr <= rx_poll_wait_ctr + 16'd1;
                    end else if (!seq_active && !seq_done) begin
                        if (state_step == 5'd0)
                            start_spi_read(S0_RX_RSR_MSB, socket_reg_read_ctrl(poll_socket));
                        else
                            start_spi_read(S0_RX_RSR_LSB, socket_reg_read_ctrl(poll_socket));
                    end else if (seq_done) begin
                        if (state_step == 5'd0) begin
                            rx_size_bytes[15:8] <= seq_rx[3];
                            state_step          <= 5'd1;
                        end else begin
                            rx_size_bytes[7:0] <= seq_rx[3];
                            last_rx_size_bytes <= {rx_size_bytes[15:8], seq_rx[3]};
                            state_step         <= 5'd0;
                            rx_poll_wait_ctr   <= 16'd0;
                            if ({rx_size_bytes[15:8], seq_rx[3]} >= UDP_RECORD_BYTES) begin
                                phy_poll_idle_count <= 16'd0;
                                active_socket <= poll_socket;
                                state <= ST_READ_RD_PTR;
                            end else if (phy_poll_idle_count == (PHY_POLL_INTERVAL_POLLS - 1)) begin
                                phy_poll_idle_count <= 16'd0;
                                state <= ST_READ_PHY;
                            end else begin
                                phy_poll_idle_count <= phy_poll_idle_count + 16'd1;
                                poll_socket <= next_socket(poll_socket);
                            end
                        end
                    end
                end

                ST_READ_RD_PTR: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 5'd0)
                            start_spi_read(S0_RX_RD_MSB, socket_reg_read_ctrl(active_socket));
                        else
                            start_spi_read(S0_RX_RD_LSB, socket_reg_read_ctrl(active_socket));
                    end else if (seq_done) begin
                        if (state_step == 5'd0) begin
                            rx_read_ptr[15:8] <= seq_rx[3];
                            state_step        <= 5'd1;
                        end else begin
                            rx_read_ptr[7:0] <= seq_rx[3];
                            state_step       <= 5'd0;
                            state            <= ST_READ_UDP_HDR;
                        end
                    end
                end

                ST_READ_UDP_HDR: begin
                    if (!seq_active && !seq_done) begin
                        start_spi_read(rx_read_ptr + {11'd0, state_step}, socket_rxbuf_read_ctrl(active_socket));
                    end else if (seq_done) begin
                        case (state_step)
                            5'd0: peer_ip[31:24]       <= seq_rx[3];
                            5'd1: peer_ip[23:16]       <= seq_rx[3];
                            5'd2: peer_ip[15:8]        <= seq_rx[3];
                            5'd3: peer_ip[7:0]         <= seq_rx[3];
                            5'd4: peer_port[15:8]      <= seq_rx[3];
                            5'd5: peer_port[7:0]       <= seq_rx[3];
                            5'd6: udp_payload_len[15:8]<= seq_rx[3];
                            5'd7: udp_payload_len[7:0] <= seq_rx[3];
                        endcase

                        if (state_step == 5'd7) begin
                            last_frame_len_bytes <= SYNTH_HDR_BYTES + {udp_payload_len[15:8], seq_rx[3]};
                            frame_index          <= 16'd0;
                            state_step           <= 5'd0;
                            if (({udp_payload_len[15:8], seq_rx[3]} <= (rx_size_bytes - UDP_RECORD_BYTES)) &&
                                ((SYNTH_HDR_BYTES + {udp_payload_len[15:8], seq_rx[3]}) <= MAX_FRAME_BYTES)) begin
                                next_rx_read_ptr <= rx_read_ptr + UDP_RECORD_BYTES + {udp_payload_len[15:8], seq_rx[3]};
                                state            <= ST_STREAM_FRAME;
                            end else begin
                                next_rx_read_ptr <= rx_read_ptr + rx_size_bytes;
                                state            <= ST_COMMIT_RX;
                            end
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_STREAM_FRAME: begin
                    if (frame_index < SYNTH_HDR_BYTES) begin
                        if (frame_ready) begin
                            frame_valid    <= 1'b1;
                            frame_data     <= synth_header_byte(frame_index, udp_payload_len, peer_ip, peer_port, local_port_for_socket(active_socket));
                            frame_sop      <= (frame_index == 16'd0);
                            frame_eop      <= (frame_index == ((SYNTH_HDR_BYTES + udp_payload_len) - 16'd1));
                            frame_src_port <= active_socket[0];
                            rx_stream_byte_count <= rx_stream_byte_count + 32'd1;

                            if (frame_index == ((SYNTH_HDR_BYTES + udp_payload_len) - 16'd1)) begin
                                frame_index <= 16'd0;
                                state       <= ST_COMMIT_RX;
                                state_step  <= 5'd0;
                            end else begin
                                frame_index <= frame_index + 16'd1;
                            end
                        end
                    end else if (!seq_active && !seq_done && frame_ready) begin
                        start_spi_read(rx_read_ptr + UDP_RECORD_BYTES + (frame_index - SYNTH_HDR_BYTES), socket_rxbuf_read_ctrl(active_socket));
                    end else if (seq_done) begin
                        frame_valid    <= 1'b1;
                        frame_data     <= seq_rx[3];
                        frame_sop      <= 1'b0;
                        frame_eop      <= (frame_index == ((SYNTH_HDR_BYTES + udp_payload_len) - 16'd1));
                        frame_src_port <= active_socket[0];
                        rx_stream_byte_count <= rx_stream_byte_count + 32'd1;

                        if (frame_index == ((SYNTH_HDR_BYTES + udp_payload_len) - 16'd1)) begin
                            frame_index <= 16'd0;
                            state       <= ST_COMMIT_RX;
                            state_step  <= 5'd0;
                        end else begin
                            frame_index <= frame_index + 16'd1;
                        end
                    end
                end

                ST_COMMIT_RX: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            5'd0: start_spi_write(S0_RX_RD_MSB, socket_reg_write_ctrl(active_socket), next_rx_read_ptr[15:8]);
                            5'd1: start_spi_write(S0_RX_RD_LSB, socket_reg_write_ctrl(active_socket), next_rx_read_ptr[7:0]);
                            5'd2: start_spi_write(S0_CR, socket_reg_write_ctrl(active_socket), S0_CR_RECV);
                            default: begin
                                rx_packet_seen   <= 1'b1;
                                rx_poll_wait_ctr <= 16'd0;
                                state            <= ST_RX_POLL;
                                state_step       <= 5'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 5'd2) begin
                            rx_packet_seen   <= 1'b1;
                            rx_commit_count  <= rx_commit_count + 32'd1;
                            rx_poll_wait_ctr <= 16'd0;
                            poll_socket      <= next_socket(active_socket);
                            state            <= ST_WAIT_RECV;
                            state_step       <= 5'd0;
                        end else begin
                            state_step <= state_step + 5'd1;
                        end
                    end
                end

                ST_WAIT_RECV: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 5'd0)
                            start_spi_read(S0_CR, socket_reg_read_ctrl(active_socket));
                        else
                            start_spi_write(S0_IR, socket_reg_write_ctrl(active_socket), 8'hFF);
                    end else if (seq_done) begin
                        if (state_step == 5'd0) begin
                            if (seq_rx[3] == 8'h00)
                                state_step <= 5'd1;
                        end else begin
                            rx_poll_wait_ctr <= 16'd0;
                            state            <= ST_RX_POLL;
                            state_step       <= 5'd0;
                        end
                    end
                end

                ST_ERROR: begin
                    init_busy  <= 1'b0;
                    init_error <= 1'b1;
                end

                default: begin
                    init_busy  <= 1'b0;
                    init_error <= 1'b1;
                    state      <= ST_ERROR;
                end
            endcase
        end
    end
endmodule
