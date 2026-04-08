`timescale 1ns/1ps

module fake_eth_source_tb;
    reg clk;
    reg rst_n;
    reg start;
    reg out_ready;
    wire out_valid;
    wire [7:0] out_data;
    wire out_sop;
    wire out_eop;
    wire [0:0] out_src_port;
    wire packet_active;
    wire done;
    wire [15:0] byte_count;

    integer seen_bytes;
    integer saw_sop;
    integer saw_eop;

    fake_eth_source #(
        .MEMORY_FILE("tb/packets/udp_allow.mem"),
        .PACKET_LENGTH(38),
        .START_DELAY(2),
        .SRC_PORT_ID(0)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .out_ready(out_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_sop(out_sop),
        .out_eop(out_eop),
        .out_src_port(out_src_port),
        .packet_active(packet_active),
        .done(done),
        .byte_count(byte_count)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk) begin
        if (out_valid && out_ready) begin
            seen_bytes = seen_bytes + 1;
            if (out_sop)
                saw_sop = 1;
            if (out_eop)
                saw_eop = 1;
        end
    end

    initial begin
        rst_n      = 1'b0;
        start      = 1'b0;
        out_ready  = 1'b1;
        seen_bytes = 0;
        saw_sop    = 0;
        saw_eop    = 0;

        #25;
        rst_n = 1'b1;
        #20;
        start = 1'b1;
        #10;
        start = 1'b0;

        wait(done);
        #10;

        if (seen_bytes != 38) begin
            $display("FAIL: expected 38 streamed bytes, got %0d", seen_bytes);
            $finish;
        end

        if (!saw_sop || !saw_eop) begin
            $display("FAIL: source did not assert both SOP and EOP");
            $finish;
        end

        $display("PASS: fake_eth_source_tb bytes=%0d src_port=%0d", seen_bytes, out_src_port);
        $finish;
    end
endmodule
