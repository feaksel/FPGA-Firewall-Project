`timescale 1ns/1ps

module w5500_tx_engine #(
    parameter SPI_CLK_DIV = 4,
    parameter MAX_FRAME_BYTES = 2048
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_init,

    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_eop,
    output wire        in_ready,

    output reg         tx_busy,
    output reg         tx_done,
    output reg         tx_error,
    output reg [31:0]  tx_count,
    output reg [3:0]   debug_state
);
    localparam ST_IDLE        = 4'd0;
    localparam ST_READ_FSR_H  = 4'd1;
    localparam ST_READ_FSR_L  = 4'd2;
    localparam ST_READ_WR_H   = 4'd3;
    localparam ST_READ_WR_L   = 4'd4;
    localparam ST_WRITE_BUF   = 4'd5;
    localparam ST_WRITE_WR_H  = 4'd6;
    localparam ST_WRITE_WR_L  = 4'd7;
    localparam ST_SEND        = 4'd8;
    localparam ST_DONE        = 4'd9;
    localparam ST_ERROR       = 4'd15;

    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_TX_FSR_MSB     = 16'h0020;
    localparam [15:0] S0_TX_FSR_LSB     = 16'h0021;
    localparam [15:0] S0_TX_WR_MSB      = 16'h0024;
    localparam [15:0] S0_TX_WR_LSB      = 16'h0025;

    localparam [7:0] CTRL_S0_REG_READ   = 8'h08;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h0C;
    localparam [7:0] CTRL_S0_TXBUF_WRITE= 8'h14;

    localparam [7:0] S0_CR_SEND         = 8'h20;

    reg [7:0]  pkt_mem [0:MAX_FRAME_BYTES-1];
    reg [15:0] wr_ptr;
    reg [15:0] pkt_len;
    reg        pkt_available;

    reg        spi_start;
    reg        spi_hold_cs;
    reg [7:0]  spi_tx_data;
    wire [7:0] spi_rx_data;
    wire       spi_busy;
    wire       spi_done;

    reg        seq_active;
    reg        seq_done;
    reg [2:0]  seq_count;
    reg [2:0]  seq_index;
    reg [7:0]  seq_tx [0:3];
    reg [7:0]  seq_rx [0:3];

    reg [3:0]  state;
    reg [15:0] tx_free_size;
    reg [15:0] tx_write_ptr;
    reg [15:0] next_tx_write_ptr;
    reg [15:0] frame_index;

    assign in_ready = start_init && !pkt_available && !tx_busy && (wr_ptr < MAX_FRAME_BYTES);

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
            seq_tx[0]   <= addr[15:8];
            seq_tx[1]   <= addr[7:0];
            seq_tx[2]   <= ctrl;
            seq_tx[3]   <= 8'h00;
            seq_count   <= 3'd4;
            seq_index   <= 3'd0;
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
            seq_index   <= 3'd0;
            seq_active  <= 1'b1;
            spi_tx_data <= addr[15:8];
            spi_hold_cs <= 1'b1;
            spi_start   <= 1'b1;
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr        <= 16'd0;
            pkt_len       <= 16'd0;
            pkt_available <= 1'b0;
            spi_start     <= 1'b0;
            spi_hold_cs   <= 1'b0;
            spi_tx_data   <= 8'd0;
            seq_active    <= 1'b0;
            seq_done      <= 1'b0;
            seq_count     <= 3'd0;
            seq_index     <= 3'd0;
            seq_rx[0]     <= 8'd0;
            seq_rx[1]     <= 8'd0;
            seq_rx[2]     <= 8'd0;
            seq_rx[3]     <= 8'd0;
            state         <= ST_IDLE;
            tx_free_size  <= 16'd0;
            tx_write_ptr  <= 16'd0;
            next_tx_write_ptr <= 16'd0;
            frame_index   <= 16'd0;
            tx_busy       <= 1'b0;
            tx_done       <= 1'b0;
            tx_error      <= 1'b0;
            tx_count      <= 32'd0;
            debug_state   <= ST_IDLE;
        end else begin
            spi_start  <= 1'b0;
            seq_done   <= 1'b0;
            tx_done    <= 1'b0;
            debug_state<= state;

            if (in_valid && in_ready) begin
                if (in_sop)
                    wr_ptr <= 16'd0;

                pkt_mem[in_sop ? 16'd0 : wr_ptr] <= in_data;

                if (in_eop) begin
                    pkt_len       <= (in_sop ? 16'd1 : (wr_ptr + 16'd1));
                    pkt_available <= 1'b1;
                    wr_ptr        <= 16'd0;
                end else begin
                    wr_ptr <= (in_sop ? 16'd1 : (wr_ptr + 16'd1));
                end
            end else if (in_valid && !in_ready) begin
                tx_error <= 1'b1;
            end

            if (seq_active && spi_done) begin
                seq_rx[seq_index] <= spi_rx_data;
                if (seq_index == (seq_count - 1'b1)) begin
                    seq_active <= 1'b0;
                    seq_done   <= 1'b1;
                end else begin
                    seq_index   <= seq_index + 1'b1;
                    spi_tx_data <= seq_tx[seq_index + 1'b1];
                    spi_hold_cs <= ((seq_index + 1'b1) != (seq_count - 1'b1));
                    spi_start   <= 1'b1;
                end
            end

            case (state)
                ST_IDLE: begin
                    tx_busy <= 1'b0;
                    if (pkt_available && start_init) begin
                        tx_busy     <= 1'b1;
                        tx_error    <= 1'b0;
                        frame_index <= 16'd0;
                        state       <= ST_READ_FSR_H;
                    end
                end

                ST_READ_FSR_H: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_FSR_MSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_free_size[15:8] <= seq_rx[3];
                        state              <= ST_READ_FSR_L;
                    end
                end

                ST_READ_FSR_L: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_FSR_LSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_free_size[7:0] <= seq_rx[3];
                        if ({tx_free_size[15:8], seq_rx[3]} >= pkt_len)
                            state <= ST_READ_WR_H;
                        else
                            state <= ST_ERROR;
                    end
                end

                ST_READ_WR_H: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_WR_MSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_write_ptr[15:8] <= seq_rx[3];
                        state              <= ST_READ_WR_L;
                    end
                end

                ST_READ_WR_L: begin
                    if (!seq_active && !seq_done)
                        start_spi_read(S0_TX_WR_LSB, CTRL_S0_REG_READ);
                    else if (seq_done) begin
                        tx_write_ptr[7:0] <= seq_rx[3];
                        frame_index       <= 16'd0;
                        state             <= ST_WRITE_BUF;
                    end
                end

                ST_WRITE_BUF: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(tx_write_ptr + frame_index, CTRL_S0_TXBUF_WRITE, pkt_mem[frame_index]);
                    else if (seq_done) begin
                        if (frame_index == (pkt_len - 16'd1)) begin
                            next_tx_write_ptr <= tx_write_ptr + pkt_len;
                            frame_index       <= 16'd0;
                            state             <= ST_WRITE_WR_H;
                        end else begin
                            frame_index <= frame_index + 16'd1;
                        end
                    end
                end

                ST_WRITE_WR_H: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_TX_WR_MSB, CTRL_S0_REG_WRITE, next_tx_write_ptr[15:8]);
                    else if (seq_done)
                        state <= ST_WRITE_WR_L;
                end

                ST_WRITE_WR_L: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_TX_WR_LSB, CTRL_S0_REG_WRITE, next_tx_write_ptr[7:0]);
                    else if (seq_done)
                        state <= ST_SEND;
                end

                ST_SEND: begin
                    if (!seq_active && !seq_done)
                        start_spi_write(S0_CR, CTRL_S0_REG_WRITE, S0_CR_SEND);
                    else if (seq_done)
                        state <= ST_DONE;
                end

                ST_DONE: begin
                    pkt_available <= 1'b0;
                    tx_busy       <= 1'b0;
                    tx_done       <= 1'b1;
                    tx_count      <= tx_count + 32'd1;
                    state         <= ST_IDLE;
                end

                ST_ERROR: begin
                    tx_error      <= 1'b1;
                    pkt_available <= 1'b0;
                    tx_busy       <= 1'b0;
                    state         <= ST_IDLE;
                end

                default: begin
                    tx_error <= 1'b1;
                    state    <= ST_ERROR;
                end
            endcase
        end
    end
endmodule
