`timescale 1ns/1ps

module w5500_tx_engine_tb;
    logic clk;
    logic rst_n;
    logic start_init;
    logic spi_sclk;
    logic spi_mosi;
    logic spi_miso;
    logic spi_cs_n;
    logic in_valid;
    logic [7:0] in_data;
    logic in_sop;
    logic in_eop;
    logic in_ready;
    logic tx_busy;
    logic tx_done;
    logic tx_error;
    logic [31:0] tx_count;
    logic [3:0] debug_state;
    logic saw_send_cmd;
    logic [15:0] tx_frame_len;
    logic [31:0] tx_send_count;

    logic [7:0] frame [0:5];
    int idx;
    int timeout;

    w5500_tx_engine #(
        .SPI_CLK_DIV(2),
        .MAX_FRAME_BYTES(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_ready(in_ready),
        .tx_busy(tx_busy),
        .tx_done(tx_done),
        .tx_error(tx_error),
        .tx_count(tx_count),
        .debug_state(debug_state)
    );

    w5500_tx_model #(
        .TXBUF_BYTES(2048)
    ) u_model (
        .rst_n(rst_n),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .cs_n(spi_cs_n),
        .saw_send_cmd(saw_send_cmd),
        .tx_frame_len(tx_frame_len),
        .tx_send_count(tx_send_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        frame[0] = 8'hDA;
        frame[1] = 8'h7A;
        frame[2] = 8'h55;
        frame[3] = 8'h01;
        frame[4] = 8'h02;
        frame[5] = 8'h03;

        rst_n      = 1'b0;
        start_init = 1'b0;
        in_valid   = 1'b0;
        in_data    = 8'd0;
        in_sop     = 1'b0;
        in_eop     = 1'b0;

        #40;
        rst_n = 1'b1;
        @(negedge clk);
        start_init = 1'b1;

        for (idx = 0; idx < 6; idx = idx + 1) begin
            @(negedge clk);
            if (!in_ready) begin
                $error("input was not ready at byte %0d", idx);
                $fatal(1);
            end
            in_valid = 1'b1;
            in_data  = frame[idx];
            in_sop   = (idx == 0);
            in_eop   = (idx == 5);
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_data  = 8'd0;
        in_sop   = 1'b0;
        in_eop   = 1'b0;

        timeout = 0;
        while ((tx_done !== 1'b1) && (timeout < 2000)) begin
            @(negedge clk);
            timeout++;
        end

        if (timeout >= 2000) begin
            $error("timeout waiting for TX completion, state=%0d tx_busy=%0b tx_error=%0b",
                   debug_state, tx_busy, tx_error);
            $fatal(1);
        end

        if (tx_error !== 1'b0) begin
            $error("tx_error asserted");
            $fatal(1);
        end
        if (tx_count !== 32'd1) begin
            $error("tx_count mismatch: got %0d", tx_count);
            $fatal(1);
        end
        if (tx_send_count !== 32'd1 || saw_send_cmd !== 1'b1) begin
            $error("model did not see SEND command");
            $fatal(1);
        end
        if (tx_frame_len !== 16'd6) begin
            $error("TX frame length mismatch: got %0d", tx_frame_len);
            $fatal(1);
        end

        for (idx = 0; idx < 6; idx = idx + 1)
            u_model.expect_sent_byte(idx, frame[idx]);

        $display("PASS: w5500_tx_engine_tb");
        $finish;
    end
endmodule
