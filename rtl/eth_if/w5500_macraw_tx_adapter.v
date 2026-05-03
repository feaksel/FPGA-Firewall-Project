`timescale 1ns/1ps

module w5500_macraw_tx_adapter #(
    parameter STARTUP_WAIT_CYCLES = 16,
    parameter RESET_ASSERT_CYCLES = 16,
    parameter RESET_RELEASE_CYCLES = 32,
    parameter SPI_CLK_DIV = 4,
    parameter MAX_FRAME_BYTES = 2048
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

    input  wire        frame_valid,
    input  wire [7:0]  frame_data,
    input  wire        frame_sop,
    input  wire        frame_eop,
    output wire        frame_ready,

    output reg         init_busy,
    output reg         init_done,
    output reg         init_error,
    output reg [31:0]  tx_count,
    output reg         tx_error,
    output reg [4:0]   debug_state,
    output reg [15:0]  last_pkt_len_dbg,
    output reg         pkt_available_dbg,
    output reg [31:0]  buf_write_start_count,
    output reg [31:0]  send_issued_count,
    output reg [31:0]  send_cleared_count,
    output reg [31:0]  send_timeout_count
);
    localparam ST_IDLE         = 5'd0;
    localparam ST_RESET        = 5'd1;
    localparam ST_VERSION      = 5'd2;
    localparam ST_COMMON_CFG   = 5'd3;
    localparam ST_SOCKET_CFG   = 5'd4;
    localparam ST_SOCKET_OPEN  = 5'd5;
    localparam ST_READY        = 5'd6;
    localparam ST_READ_FSR_MSB = 5'd7;
    localparam ST_READ_FSR_LSB = 5'd8;
    localparam ST_READ_WR_MSB  = 5'd9;
    localparam ST_READ_WR_LSB  = 5'd10;
    localparam ST_WRITE_BUF    = 5'd11;
    localparam ST_WRITE_WR_MSB = 5'd12;
    localparam ST_WRITE_WR_LSB = 5'd13;
    localparam ST_SEND         = 5'd14;
    localparam ST_ERROR        = 5'd15;
    localparam ST_WAIT_SEND    = 5'd16;

    localparam [15:0] COMMON_MR         = 16'h0000;
    localparam [15:0] COMMON_VERSIONR   = 16'h0039;
    localparam [15:0] S0_MR             = 16'h0000;
    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_SR             = 16'h0003;
    localparam [15:0] S0_RXBUF_SIZE     = 16'h001E;
    localparam [15:0] S0_TXBUF_SIZE     = 16'h001F;
    localparam [15:0] S0_TX_FSR_MSB     = 16'h0020;
    localparam [15:0] S0_TX_FSR_LSB     = 16'h0021;
    localparam [15:0] S0_TX_WR_MSB      = 16'h0024;
    localparam [15:0] S0_TX_WR_LSB      = 16'h0025;

    localparam [7:0] CTRL_COMMON_READ   = 8'h00;
    localparam [7:0] CTRL_COMMON_WRITE  = 8'h04;
    localparam [7:0] CTRL_S0_REG_READ   = 8'h08;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h0C;
    localparam [7:0] CTRL_S0_TXBUF_WRITE= 8'h14;

    localparam [7:0] W5500_VERSION      = 8'h04;
    localparam [7:0] S0_MR_MACRAW       = 8'h04;
    localparam [7:0] S0_CR_OPEN         = 8'h01;
    localparam [7:0] S0_CR_SEND         = 8'h20;
    localparam [7:0] S0_STATUS_MACRAW   = 8'h42;
    localparam [7:0] SOCKET_BUF_16KB    = 8'h10;

    reg [4:0]  state;
    reg [2:0]  state_step;
    reg [31:0] wait_ctr;
    reg [31:0] send_wait_ctr;

    reg [7:0]  pkt_mem [0:MAX_FRAME_BYTES-1];
    reg [15:0] wr_ptr;
    reg [15:0] pkt_len;
    reg        pkt_available;
    reg [15:0] tx_free_size;
    reg [15:0] tx_write_ptr;
    reg [15:0] next_tx_write_ptr;
    reg [15:0] frame_index;

    reg        spi_start;
    reg        spi_hold_cs;
    reg [7:0]  spi_tx_data;
    wire [7:0] spi_rx_data;
    wire       spi_done;

    reg        seq_active;
    reg        seq_done;
    reg [15:0] seq_count;
    reg [15:0] seq_index;
    reg        seq_txbuf_burst;
    reg [7:0]  seq_tx [0:3];
    reg [7:0]  seq_rx [0:3];

    assign frame_ready = init_done && !pkt_available && (state == ST_READY) && (wr_ptr < MAX_FRAME_BYTES);

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
        .busy(),
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
            seq_tx[0]   <= addr[15:8];
            seq_tx[1]   <= addr[7:0];
            seq_tx[2]   <= ctrl;
            seq_tx[3]   <= 8'h00;
            seq_count   <= 3'd4;
            seq_index   <= 16'd0;
            seq_txbuf_burst <= 1'b0;
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
            seq_count   <= 3'd4;
            seq_index   <= 16'd0;
            seq_txbuf_burst <= 1'b0;
            seq_active  <= 1'b1;
            spi_tx_data <= addr[15:8];
            spi_hold_cs <= 1'b1;
            spi_start   <= 1'b1;
        end
    endtask

    task start_spi_txbuf_burst;
        input [15:0] addr;
        begin
            seq_tx[0]        <= addr[15:8];
            seq_tx[1]        <= addr[7:0];
            seq_tx[2]        <= CTRL_S0_TXBUF_WRITE;
            seq_tx[3]        <= pkt_mem[0];
            seq_count        <= pkt_len + 16'd3;
            seq_index        <= 16'd0;
            seq_txbuf_burst  <= 1'b1;
            seq_active       <= 1'b1;
            spi_tx_data      <= addr[15:8];
            spi_hold_cs      <= 1'b1;
            spi_start        <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_IDLE;
            state_step        <= 3'd0;
            wait_ctr          <= 32'd0;
            send_wait_ctr     <= 32'd0;
            w5500_reset_n     <= 1'b1;
            wr_ptr            <= 16'd0;
            pkt_len           <= 16'd0;
            pkt_available     <= 1'b0;
            tx_free_size      <= 16'd0;
            tx_write_ptr      <= 16'd0;
            next_tx_write_ptr <= 16'd0;
            frame_index       <= 16'd0;
            spi_start         <= 1'b0;
            spi_hold_cs       <= 1'b0;
            spi_tx_data       <= 8'd0;
            seq_active        <= 1'b0;
            seq_done          <= 1'b0;
            seq_count         <= 16'd0;
            seq_index         <= 16'd0;
            seq_txbuf_burst   <= 1'b0;
            init_busy         <= 1'b0;
            init_done         <= 1'b0;
            init_error        <= 1'b0;
            tx_count          <= 32'd0;
            tx_error          <= 1'b0;
            debug_state       <= 5'd0;
            last_pkt_len_dbg  <= 16'd0;
            pkt_available_dbg <= 1'b0;
            buf_write_start_count <= 32'd0;
            send_issued_count     <= 32'd0;
            send_cleared_count    <= 32'd0;
            send_timeout_count    <= 32'd0;
        end else begin
            spi_start   <= 1'b0;
            seq_done    <= 1'b0;
            debug_state <= state;
            pkt_available_dbg <= pkt_available;

            if (frame_valid && frame_ready) begin
                if (frame_sop)
                    wr_ptr <= 16'd0;
                pkt_mem[frame_sop ? 16'd0 : wr_ptr] <= frame_data;
                if (frame_eop) begin
                    pkt_len          <= (frame_sop ? 16'd1 : (wr_ptr + 16'd1));
                    last_pkt_len_dbg <= (frame_sop ? 16'd1 : (wr_ptr + 16'd1));
                    pkt_available    <= 1'b1;
                    wr_ptr           <= 16'd0;
                end else begin
                    wr_ptr <= (frame_sop ? 16'd1 : (wr_ptr + 16'd1));
                end
            end

            if (seq_active && spi_done) begin
                if (seq_index < 16'd4)
                    seq_rx[seq_index[1:0]] <= spi_rx_data;
                if (seq_index == (seq_count - 1'b1)) begin
                    seq_active      <= 1'b0;
                    seq_done        <= 1'b1;
                    seq_txbuf_burst <= 1'b0;
                end else begin
                    seq_index <= seq_index + 1'b1;
                    if (seq_txbuf_burst && ((seq_index + 1'b1) >= 16'd3))
                        spi_tx_data <= pkt_mem[(seq_index + 1'b1) - 16'd3];
                    else begin
                        case (seq_index[1:0])
                            2'd0: spi_tx_data <= seq_tx[1];
                            2'd1: spi_tx_data <= seq_tx[2];
                            2'd2: spi_tx_data <= seq_tx[3];
                            default: spi_tx_data <= seq_tx[0];
                        endcase
                    end
                    spi_hold_cs <= ((seq_index + 1'b1) != (seq_count - 1'b1));
                    spi_start   <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    init_busy     <= 1'b0;
                    init_done     <= 1'b0;
                    init_error    <= 1'b0;
                    w5500_reset_n <= 1'b1;
                    state_step    <= 3'd0;
                    wait_ctr      <= 32'd0;
                    if (start_init) begin
                        init_busy     <= 1'b1;
                        w5500_reset_n <= 1'b0;
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
                    end else if (wait_ctr == (RESET_RELEASE_CYCLES + STARTUP_WAIT_CYCLES - 1)) begin
                        wait_ctr <= 32'd0;
                        state    <= ST_VERSION;
                    end else begin
                        wait_ctr <= wait_ctr + 32'd1;
                    end
                end

                ST_VERSION: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(COMMON_VERSIONR, CTRL_COMMON_READ);
                    else if (seq_done) begin
                        if (seq_rx[3] == W5500_VERSION)
                            state <= ST_COMMON_CFG;
                        else
                            state <= ST_ERROR;
                    end
                end

                ST_COMMON_CFG: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(COMMON_MR, CTRL_COMMON_WRITE, 8'h00);
                    else if (seq_done) begin
                        state      <= ST_SOCKET_CFG;
                        state_step <= 3'd0;
                    end
                end

                ST_SOCKET_CFG: begin
                    if (!seq_active && !seq_done) begin
                        case (state_step)
                            3'd0: start_spi_write(S0_RXBUF_SIZE, CTRL_S0_REG_WRITE, SOCKET_BUF_16KB);
                            3'd1: start_spi_write(S0_TXBUF_SIZE, CTRL_S0_REG_WRITE, SOCKET_BUF_16KB);
                            3'd2: start_spi_write(S0_MR, CTRL_S0_REG_WRITE, S0_MR_MACRAW);
                            default: state <= ST_SOCKET_OPEN;
                        endcase
                    end else if (seq_done) begin
                        if (state_step == 3'd2) begin
                            state      <= ST_SOCKET_OPEN;
                            state_step <= 3'd0;
                        end else begin
                            state_step <= state_step + 3'd1;
                        end
                    end
                end

                ST_SOCKET_OPEN: begin
                    if (!seq_active && !seq_done) begin
                        if (state_step == 3'd0)
                            start_spi_write(S0_CR, CTRL_S0_REG_WRITE, S0_CR_OPEN);
                        else
                            start_spi_read(S0_SR, CTRL_S0_REG_READ);
                    end else if (seq_done) begin
                        if (state_step == 3'd0) begin
                            state_step <= 3'd1;
                        end else if (seq_rx[3] == S0_STATUS_MACRAW) begin
                            init_busy <= 1'b0;
                            init_done <= 1'b1;
                            state     <= ST_READY;
                        end
                    end
                end

                ST_READY: begin
                    init_done <= 1'b1;
                    if (pkt_available) begin
                        frame_index <= 16'd0;
                        state       <= ST_READ_FSR_MSB;
                    end
                end

                ST_READ_FSR_MSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_FSR_MSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_free_size[15:8] <= seq_rx[3];
                        state              <= ST_READ_FSR_LSB;
                    end
                end

                ST_READ_FSR_LSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_FSR_LSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_free_size[7:0] <= seq_rx[3];
                        if ({tx_free_size[15:8], seq_rx[3]} >= pkt_len)
                            state <= ST_READ_WR_MSB;
                        else begin
                            state <= ST_READ_FSR_MSB;
                        end
                    end
                end

                ST_READ_WR_MSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_WR_MSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_write_ptr[15:8] <= seq_rx[3];
                        state              <= ST_READ_WR_LSB;
                    end
                end

                ST_READ_WR_LSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_WR_LSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_write_ptr[7:0] <= seq_rx[3];
                        frame_index       <= 16'd0;
                        state             <= ST_WRITE_BUF;
                    end
                end

                ST_WRITE_BUF: begin
                    if (!seq_active && !seq_done) begin
                        start_spi_txbuf_burst(tx_write_ptr);
                        buf_write_start_count <= buf_write_start_count + 32'd1;
                    end else if (seq_done) begin
                        next_tx_write_ptr <= tx_write_ptr + pkt_len;
                        frame_index       <= 16'd0;
                        state             <= ST_WRITE_WR_MSB;
                    end
                end

                ST_WRITE_WR_MSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_TX_WR_MSB, CTRL_S0_REG_WRITE, next_tx_write_ptr[15:8]);
                    else if (seq_done)
                        state <= ST_WRITE_WR_LSB;
                end

                ST_WRITE_WR_LSB: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_TX_WR_LSB, CTRL_S0_REG_WRITE, next_tx_write_ptr[7:0]);
                    else if (seq_done)
                        state <= ST_SEND;
                end

                ST_SEND: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_CR, CTRL_S0_REG_WRITE, S0_CR_SEND);
                    else if (seq_done) begin
                        send_issued_count <= send_issued_count + 32'd1;
                        send_wait_ctr     <= 32'd0;
                        state             <= ST_WAIT_SEND;
                    end
                end

                ST_WAIT_SEND: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_CR, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        if (seq_rx[3] == 8'h00) begin
                            tx_count           <= tx_count + 32'd1;
                            send_cleared_count <= send_cleared_count + 32'd1;
                            pkt_available      <= 1'b0;
                            send_wait_ctr      <= 32'd0;
                            state              <= ST_READY;
                        end else if (send_wait_ctr == 32'd5_000_000) begin
                            tx_error           <= 1'b1;
                            send_timeout_count <= send_timeout_count + 32'd1;
                            pkt_available      <= 1'b0;
                            send_wait_ctr      <= 32'd0;
                            state              <= ST_READY;
                        end else begin
                            send_wait_ctr <= send_wait_ctr + 32'd1;
                        end
                    end
                end

                ST_ERROR: begin
                    init_busy  <= 1'b0;
                    init_error <= 1'b1;
                    tx_error   <= 1'b1;
                end

                default: begin
                    state <= ST_ERROR;
                end
            endcase
        end
    end
endmodule
