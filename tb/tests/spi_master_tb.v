`timescale 1ns/1ps

module spi_master_tb;
    reg clk;
    reg rst_n;
    reg start;
    reg hold_cs;
    reg [7:0] tx_data;
    wire [7:0] rx_data;
    wire busy;
    wire done;
    wire sclk;
    wire mosi;
    reg miso;
    wire cs_n;

    reg [7:0] slave_tx;
    reg [7:0] slave_rx;
    integer slave_idx;

    spi_master #(
        .CLK_DIV(2),
        .CPOL(0),
        .CPHA(0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .hold_cs(hold_cs),
        .tx_data(tx_data),
        .rx_data(rx_data),
        .busy(busy),
        .done(done),
        .sclk(sclk),
        .mosi(mosi),
        .miso(miso),
        .cs_n(cs_n)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(negedge cs_n) begin
        slave_tx  <= 8'hA5;
        slave_rx  <= 8'h00;
        slave_idx <= 7;
        miso      <= 1'b1;
    end

    always @(posedge sclk) begin
        if (!cs_n)
            slave_rx[slave_idx] <= mosi;
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            if (slave_idx > 0) begin
                slave_idx <= slave_idx - 1;
                miso      <= slave_tx[slave_idx - 1];
            end else begin
                miso <= 1'b0;
            end
        end
    end

    initial begin
        rst_n    = 1'b0;
        start    = 1'b0;
        hold_cs  = 1'b0;
        tx_data  = 8'h3C;
        miso     = 1'b0;
        slave_tx = 8'hA5;
        slave_rx = 8'h00;
        slave_idx = 7;

        #25;
        rst_n = 1'b1;

        @(posedge clk);
        start <= 1'b1;
        @(posedge clk);
        start <= 1'b0;

        wait(done);
        @(posedge clk);

        if (rx_data !== 8'hA5) begin
            $display("FAIL: expected rx_data=0xA5 got 0x%02h", rx_data);
            $finish;
        end

        if (slave_rx !== 8'h3C) begin
            $display("FAIL: expected slave_rx=0x3C got 0x%02h", slave_rx);
            $finish;
        end

        $display("PASS: spi_master_tb");
        $finish;
    end
endmodule
