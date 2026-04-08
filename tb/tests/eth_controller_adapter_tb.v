`timescale 1ns/1ps

module eth_controller_adapter_tb;
    reg clk;
    reg rst_n;
    reg start_init;
    wire spi_sclk;
    wire spi_mosi;
    reg spi_miso;
    wire spi_cs_n;
    wire init_busy;
    wire init_done;
    wire init_error;
    wire frame_valid;
    wire [7:0] frame_data;
    wire frame_sop;
    wire frame_eop;
    wire [0:0] frame_src_port;
    reg frame_ready;
    wire [3:0] debug_state;

    ethernet_controller_adapter #(
        .STARTUP_WAIT_CYCLES(4),
        .SPI_CLK_DIV(2)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start_init(start_init),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso),
        .spi_cs_n(spi_cs_n),
        .init_busy(init_busy),
        .init_done(init_done),
        .init_error(init_error),
        .frame_valid(frame_valid),
        .frame_data(frame_data),
        .frame_sop(frame_sop),
        .frame_eop(frame_eop),
        .frame_src_port(frame_src_port),
        .frame_ready(frame_ready),
        .debug_state(debug_state)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        rst_n       = 1'b0;
        start_init  = 1'b0;
        spi_miso    = 1'b0;
        frame_ready = 1'b1;

        #30;
        rst_n = 1'b1;

        @(posedge clk);
        start_init <= 1'b1;
        @(posedge clk);
        start_init <= 1'b0;

        wait(init_done);
        @(posedge clk);

        if (init_error) begin
            $display("FAIL: adapter raised init_error");
            $finish;
        end

        if (debug_state != 4'd10) begin
            $display("FAIL: adapter did not reach READY state, debug_state=%0d", debug_state);
            $finish;
        end

        $display("PASS: eth_controller_adapter_tb");
        $finish;
    end
endmodule
