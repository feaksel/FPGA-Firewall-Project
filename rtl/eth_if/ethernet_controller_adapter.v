`timescale 1ns/1ps

module ethernet_controller_adapter #(
    parameter STARTUP_WAIT_CYCLES = 16,
    parameter RESET_ASSERT_CYCLES = 16,
    parameter RESET_RELEASE_CYCLES = 32,
    parameter RX_POLL_WAIT_CYCLES = 32,
    parameter SPI_CLK_DIV = 4,
    parameter MAX_FRAME_BYTES = 512
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
    localparam ST_READ_LEN     = 4'd8;
    localparam ST_STREAM_FRAME = 4'd9;
    localparam ST_COMMIT_RX    = 4'd10;
    localparam ST_WAIT_RECV    = 4'd11;
    localparam ST_READ_PHY     = 4'd12;
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
    // MACRAW mode with MFEN=1. Round-17 readback proved SHAR is programmed as
    // 02:00:00:DE:AD:0A; the reliable demo path now uses normal UDP plus a
    // static ARP entry so PC1 sends unicast frames directly to that address.
    localparam [7:0] S0_MR_MACRAW       = 8'h84;
    localparam [7:0] S0_CR_OPEN         = 8'h01;
    localparam [7:0] S0_CR_RECV         = 8'h40;
    localparam [7:0] S0_STATUS_MACRAW   = 8'h42;
    localparam [7:0] SOCKET_BUF_16KB    = 8'h10;

    reg [3:0]  state;
    reg [4:0]  state_step;
    reg [31:0] wait_ctr;
    reg [15:0] rx_poll_wait_ctr;

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
    reg        seq_rxbuf_burst;
    reg [7:0]  seq_tx [0:3];
    reg [7:0]  seq_rx [0:3];

    reg [15:0] rx_size_bytes;
    reg [15:0] rx_read_ptr;
    reg [15:0] frame_len_bytes;
    reg [15:0] frame_index;
    reg [15:0] next_rx_read_ptr;
    reg [3:0]  bad_len_streak;

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

    task start_spi_read;
        input [15:0] addr;
        input [7:0]  ctrl;
        begin
            seq_tx[0]  <= addr[15:8];
            seq_tx[1]  <= addr[7:0];
            seq_tx[2]  <= ctrl;
            seq_tx[3]  <= 8'h00;
            seq_count  <= 3'd4;
            seq_index  <= 3'd0;
            seq_active <= 1'b1;
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
            seq_tx[0]  <= addr[15:8];
            seq_tx[1]  <= addr[7:0];
            seq_tx[2]  <= ctrl;
            seq_tx[3]  <= data;
            seq_count  <= 3'd4;
            seq_index  <= 3'd0;
            seq_active <= 1'b1;
            spi_tx_data <= addr[15:8];
            spi_hold_cs <= 1'b1;
            spi_start   <= 1'b1;
        end
    endtask

    task start_spi_rxbuf_burst;
        input [15:0] addr;
        begin
            seq_tx[0]       <= addr[15:8];
            seq_tx[1]       <= addr[7:0];
            seq_tx[2]       <= CTRL_S0_RXBUF_READ;
            seq_tx[3]       <= 8'h00;
            seq_count       <= frame_len_bytes + 16'd3;
            seq_index       <= 16'd0;
            seq_rxbuf_burst <= 1'b1;
            seq_active      <= 1'b1;
            spi_tx_data     <= addr[15:8];
            spi_hold_cs     <= 1'b1;
            spi_start       <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= ST_IDLE;
            state_step       <= 3'd0;
            wait_ctr         <= 16'd0;
            rx_poll_wait_ctr <= 16'd0;
            w5500_reset_n    <= 1'b1;
            spi_start        <= 1'b0;
            spi_hold_cs      <= 1'b0;
            spi_tx_data      <= 8'd0;
            seq_active       <= 1'b0;
            seq_done         <= 1'b0;
            seq_count        <= 16'd0;
            seq_index        <= 16'd0;
            seq_rxbuf_burst  <= 1'b0;
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
            shar_value       <= 48'd0;
            sipr_value       <= 32'd0;
            debug_state      <= ST_IDLE;
            rx_size_bytes    <= 16'd0;
            rx_read_ptr      <= 16'd0;
            frame_len_bytes  <= 16'd0;
            frame_index      <= 16'd0;
            next_rx_read_ptr <= 16'd0;
            bad_len_streak   <= 4'd0;
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

                if (seq_rxbuf_burst && (seq_index >= 16'd3)) begin
                    frame_valid    <= 1'b1;
                    frame_data     <= spi_rx_data;
                    frame_sop      <= (seq_index == 16'd3);
                    frame_eop      <= (seq_index == (seq_count - 1'b1));
                    frame_src_port <= 1'b0;
                    rx_stream_byte_count <= rx_stream_byte_count + 32'd1;
                end

                if (seq_index == (seq_count - 1'b1)) begin
                    seq_active      <= 1'b0;
                    seq_done        <= 1'b1;
                    seq_rxbuf_burst <= 1'b0;
                end else begin
                    seq_index   <= seq_index + 1'b1;
                    if (seq_rxbuf_burst && ((seq_index + 1'b1) >= 16'd3))
                        spi_tx_data <= 8'h00;
                    else
                        spi_tx_data <= seq_tx[seq_index[1:0] + 2'd1];
                    spi_hold_cs <= ((seq_index + 1'b1) != (seq_count - 1'b1));
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
                    state_step     <= 3'd0;
                    wait_ctr       <= 16'd0;
                    if (start_init) begin
                        init_busy      <= 1'b1;
                        w5500_reset_n  <= 1'b0;
                        wait_ctr       <= 16'd0;
                        state          <= ST_RESET;
                    end
                end

                ST_RESET: begin
                    if (!w5500_reset_n) begin
                        if (wait_ctr == (RESET_ASSERT_CYCLES - 1'b1)) begin
                            w5500_reset_n <= 1'b1;
                            wait_ctr      <= 16'd0;
                        end else begin
                            wait_ctr <= wait_ctr + 1'b1;
                        end
                    end else begin
                        if (wait_ctr == (RESET_RELEASE_CYCLES + STARTUP_WAIT_CYCLES - 1'b1)) begin
                            wait_ctr   <= 16'd0;
                            state_step <= 3'd0;
                            state      <= ST_VERSION;
                        end else begin
                            wait_ctr <= wait_ctr + 1'b1;
                        end
                    end
                end

                ST_VERSION: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(COMMON_VERSIONR, CTRL_COMMON_READ);
                    else if (seq_done) begin
                        if (seq_rx[3] == W5500_VERSION) begin
                            state      <= ST_COMMON_CFG;
                            state_step <= 3'd0;
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
                                state_step <= 3'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 5'd18) begin
                            state      <= ST_SOCKET_CFG;
                            state_step <= 3'd0;
                        end else begin
                            state_step <= state_step + 1'b1;
                        end
                    end
                end

                ST_SOCKET_CFG: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            3'd0: start_spi_write(S0_RXBUF_SIZE, CTRL_S0_REG_WRITE, SOCKET_BUF_16KB);
                            3'd1: start_spi_write(S0_TXBUF_SIZE, CTRL_S0_REG_WRITE, SOCKET_BUF_16KB);
                            3'd2: start_spi_write(S0_MR, CTRL_S0_REG_WRITE, S0_MR_MACRAW);
                            default: begin
                                state      <= ST_SOCKET_OPEN;
                                state_step <= 3'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 3'd2) begin
                            state      <= ST_SOCKET_OPEN;
                            state_step <= 3'd0;
                        end else begin
                            state_step <= state_step + 1'b1;
                        end
                    end
                end

                ST_SOCKET_OPEN: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            3'd0: start_spi_write(S0_CR, CTRL_S0_REG_WRITE, S0_CR_OPEN);
                            3'd1: start_spi_read(S0_SR, CTRL_S0_REG_READ);
                            default: begin
                                init_busy      <= 1'b0;
                                init_done      <= 1'b1;
                                rx_poll_wait_ctr<= 16'd0;
                                state          <= ST_READ_PHY;
                                state_step     <= 3'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            state_step <= 3'd1;
                        end else if (seq_rx[3] == S0_STATUS_MACRAW) begin
                            init_busy       <= 1'b0;
                            init_done       <= 1'b1;
                            rx_poll_wait_ctr<= 16'd0;
                            state           <= ST_READ_PHY;
                            state_step      <= 3'd0;
                        end
                    end
                end

                ST_RX_POLL: begin
                    init_done <= 1'b1;
                    if (rx_poll_wait_ctr != RX_POLL_WAIT_CYCLES && w5500_int_n) begin
                        rx_poll_wait_ctr <= rx_poll_wait_ctr + 1'b1;
                    end else if (!seq_active && !seq_done) begin
                        if (state_step == 3'd0)
                            start_spi_read(S0_RX_RSR_MSB, CTRL_S0_REG_READ);
                        else
                            start_spi_read(S0_RX_RSR_LSB, CTRL_S0_REG_READ);
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            rx_size_bytes[15:8] <= seq_rx[3];
                            state_step          <= 3'd1;
                        end else begin
                            rx_size_bytes[7:0] <= seq_rx[3];
                            last_rx_size_bytes  <= {rx_size_bytes[15:8], seq_rx[3]};
                            state_step         <= 3'd0;
                            rx_poll_wait_ctr   <= 16'd0;
                            if ({rx_size_bytes[15:8], seq_rx[3]} > 16'd2)
                                state <= ST_READ_RD_PTR;
                            else if (rx_commit_count[3:0] != phy_read_count[3:0])
                                state <= ST_READ_PHY;
                        end
                    end
                end

                ST_READ_PHY: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            3'd0: start_spi_read(COMMON_PHYCFGR, CTRL_COMMON_READ);
                            3'd1: start_spi_read(S0_MR, CTRL_S0_REG_READ);
                            3'd2: start_spi_read(COMMON_SHAR0, CTRL_COMMON_READ);
                            3'd3: start_spi_read(COMMON_SHAR1, CTRL_COMMON_READ);
                            3'd4: start_spi_read(COMMON_SHAR2, CTRL_COMMON_READ);
                            3'd5: start_spi_read(COMMON_SHAR3, CTRL_COMMON_READ);
                            3'd6: start_spi_read(COMMON_SHAR4, CTRL_COMMON_READ);
                            3'd7: start_spi_read(COMMON_SHAR5, CTRL_COMMON_READ);
                            5'd8: start_spi_read(COMMON_SIPR0, CTRL_COMMON_READ);
                            5'd9: start_spi_read(COMMON_SIPR1, CTRL_COMMON_READ);
                            5'd10: start_spi_read(COMMON_SIPR2, CTRL_COMMON_READ);
                            5'd11: start_spi_read(COMMON_SIPR3, CTRL_COMMON_READ);
                        endcase
                    end
                    else if (seq_done) begin
                        case (state_step)
                            3'd0: phy_cfgr_value    <= seq_rx[3];
                            3'd1: socket_mode_value <= seq_rx[3];
                            3'd2: shar_value[47:40] <= seq_rx[3];
                            3'd3: shar_value[39:32] <= seq_rx[3];
                            3'd4: shar_value[31:24] <= seq_rx[3];
                            3'd5: shar_value[23:16] <= seq_rx[3];
                            3'd6: shar_value[15:8]  <= seq_rx[3];
                            3'd7: shar_value[7:0]   <= seq_rx[3];
                            5'd8: sipr_value[31:24] <= seq_rx[3];
                            5'd9: sipr_value[23:16] <= seq_rx[3];
                            5'd10: sipr_value[15:8] <= seq_rx[3];
                            5'd11: sipr_value[7:0]  <= seq_rx[3];
                        endcase

                        if (state_step == 5'd11) begin
                            phy_read_count   <= rx_commit_count;
                            rx_poll_wait_ctr <= 16'd0;
                            state            <= ST_RX_POLL;
                            state_step       <= 3'd0;
                        end else begin
                            state_step <= state_step + 1'b1;
                        end
                    end
                end

                ST_READ_RD_PTR: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 3'd0)
                            start_spi_read(S0_RX_RD_MSB, CTRL_S0_REG_READ);
                        else
                            start_spi_read(S0_RX_RD_LSB, CTRL_S0_REG_READ);
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            rx_read_ptr[15:8] <= seq_rx[3];
                            state_step        <= 3'd1;
                        end else begin
                            rx_read_ptr[7:0] <= seq_rx[3];
                            state_step       <= 3'd0;
                            state            <= ST_READ_LEN;
                        end
                    end
                end

                ST_READ_LEN: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 3'd0)
                            start_spi_read(rx_read_ptr, CTRL_S0_RXBUF_READ);
                        else
                            start_spi_read(rx_read_ptr + 16'd1, CTRL_S0_RXBUF_READ);
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            frame_len_bytes[15:8] <= seq_rx[3];
                            state_step            <= 3'd1;
                        end else begin
                            frame_len_bytes[7:0] <= seq_rx[3];
                            last_frame_len_bytes <= {frame_len_bytes[15:8], seq_rx[3]};
                            state_step           <= 3'd0;
                            frame_index          <= 16'd0;
                            if (({frame_len_bytes[15:8], seq_rx[3]} != 16'd0) &&
                                ({frame_len_bytes[15:8], seq_rx[3]} <= MAX_FRAME_BYTES) &&
                                ({frame_len_bytes[15:8], seq_rx[3]} <= (rx_size_bytes - 16'd2))) begin
                                next_rx_read_ptr <= rx_read_ptr + {frame_len_bytes[15:8], seq_rx[3]} + 16'd2;
                                bad_len_streak   <= 4'd0;
                                state            <= ST_STREAM_FRAME;
                            end else begin
                                // Length is bogus. Advance a bounded amount so we
                                // don't flush legitimate frames buffered behind a
                                // single corrupted length header. If several
                                // consecutive bounded skips still land inside
                                // frame data, flush the current RX occupancy to
                                // resync on future frames from the live sender.
                                if (bad_len_streak >= 4'd3) begin
                                    next_rx_read_ptr <= rx_read_ptr + rx_size_bytes;
                                    bad_len_streak   <= 4'd0;
                                end else if (rx_size_bytes <= 16'd1520) begin
                                    next_rx_read_ptr <= rx_read_ptr + rx_size_bytes;
                                    bad_len_streak   <= bad_len_streak + 4'd1;
                                end else begin
                                    next_rx_read_ptr <= rx_read_ptr + 16'd1520;
                                    bad_len_streak   <= bad_len_streak + 4'd1;
                                end
                                state            <= ST_COMMIT_RX;
                            end
                        end
                    end
                end

                ST_STREAM_FRAME: begin
                    if (!seq_active && !seq_done && frame_ready) begin
                        start_spi_read(rx_read_ptr + 16'd2 + frame_index, CTRL_S0_RXBUF_READ);
                    end else if (seq_done) begin
                        frame_valid    <= 1'b1;
                        frame_data     <= seq_rx[3];
                        frame_sop      <= (frame_index == 16'd0);
                        frame_eop      <= (frame_index == (frame_len_bytes - 1'b1));
                        frame_src_port <= 1'b0;
                        rx_stream_byte_count <= rx_stream_byte_count + 32'd1;

                        if (frame_index == (frame_len_bytes - 1'b1)) begin
                            frame_index <= 16'd0;
                            state       <= ST_COMMIT_RX;
                            state_step  <= 3'd0;
                        end else begin
                            frame_index <= frame_index + 1'b1;
                        end
                    end
                end

                ST_COMMIT_RX: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            3'd0: start_spi_write(S0_RX_RD_MSB, CTRL_S0_REG_WRITE, next_rx_read_ptr[15:8]);
                            3'd1: start_spi_write(S0_RX_RD_LSB, CTRL_S0_REG_WRITE, next_rx_read_ptr[7:0]);
                            3'd2: start_spi_write(S0_CR, CTRL_S0_REG_WRITE, S0_CR_RECV);
                            default: begin
                                rx_packet_seen    <= 1'b1;
                                rx_poll_wait_ctr  <= 16'd0;
                                state             <= ST_RX_POLL;
                                state_step        <= 3'd0;
                            end
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 3'd2) begin
                            rx_packet_seen   <= 1'b1;
                            rx_commit_count  <= rx_commit_count + 32'd1;
                            rx_poll_wait_ctr <= 16'd0;
                            state            <= ST_WAIT_RECV;
                            state_step       <= 3'd0;
                        end else begin
                            state_step <= state_step + 1'b1;
                        end
                    end
                end

                ST_WAIT_RECV: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 3'd0)
                            start_spi_read(S0_CR, CTRL_S0_REG_READ);
                        else
                            start_spi_write(S0_IR, CTRL_S0_REG_WRITE, 8'hFF);
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            if (seq_rx[3] == 8'h00) begin
                                state_step <= 3'd1;
                            end
                        end else begin
                            rx_poll_wait_ctr <= 16'd0;
                            state            <= ST_RX_POLL;
                            state_step       <= 3'd0;
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
