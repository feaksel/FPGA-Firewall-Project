`timescale 1ns/1ps

module packet_buffer_tb;
    reg clk;
    reg rst_n;
    reg in_valid;
    reg [7:0] in_data;
    reg in_sop;
    reg in_eop;
    reg [0:0] in_src_port;
    wire in_ready;
    reg rd_start;
    wire out_valid;
    wire [7:0] out_data;
    wire out_sop;
    wire out_eop;
    wire [0:0] out_src_port;
    reg out_ready;
    wire [15:0] pkt_len;
    wire pkt_done;
    wire pkt_available;
    wire overflow_error;
    reg saw_pkt_done;

    reg [7:0] sample_mem [0:4];
    integer idx;
    integer out_count;

    packet_buffer #(
        .MAX_PKT_BYTES(64)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_src_port(in_src_port),
        .in_ready(in_ready),
        .rd_start(rd_start),
        .discard(1'b0),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_sop(out_sop),
        .out_eop(out_eop),
        .out_src_port(out_src_port),
        .out_ready(out_ready),
        .pkt_len(pkt_len),
        .pkt_done(pkt_done),
        .pkt_available(pkt_available),
        .overflow_error(overflow_error)
    );

    initial begin
        sample_mem[0] = 8'hDE;
        sample_mem[1] = 8'hAD;
        sample_mem[2] = 8'hBE;
        sample_mem[3] = 8'hEF;
        sample_mem[4] = 8'h42;
    end

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            saw_pkt_done <= 1'b0;
        else if (pkt_done)
            saw_pkt_done <= 1'b1;
    end

    initial begin
        rst_n       = 1'b0;
        in_valid    = 1'b0;
        in_data     = 8'd0;
        in_sop      = 1'b0;
        in_eop      = 1'b0;
        in_src_port = 1'b1;
        rd_start    = 1'b0;
        out_ready   = 1'b1;
        out_count   = 0;
        saw_pkt_done= 1'b0;

        #25;
        rst_n = 1'b1;

        for (idx = 0; idx < 5; idx = idx + 1) begin
            @(negedge clk);
            in_valid = 1'b1;
            in_data  = sample_mem[idx];
            in_sop   = (idx == 0);
            in_eop   = (idx == 4);
        end

        @(negedge clk);
        in_valid = 1'b0;
        in_sop   = 1'b0;
        in_eop   = 1'b0;

        wait(pkt_done);
        @(negedge clk);
        if (!saw_pkt_done || !pkt_available || pkt_len != 16'd5 || overflow_error) begin
            $display("FAIL: buffer write path pkt_done=%0d pkt_available=%0d pkt_len=%0d overflow_error=%0d",
                     saw_pkt_done, pkt_available, pkt_len, overflow_error);
            $finish;
        end

        @(negedge clk);
        rd_start = 1'b1;
        @(negedge clk);
        rd_start = 1'b0;

        while (pkt_available || out_valid) begin
            @(posedge clk);
            if (out_valid && out_ready) begin
                if (out_data !== sample_mem[out_count]) begin
                    $display("FAIL: buffer replay mismatch at idx=%0d got=%02h expected=%02h",
                             out_count, out_data, sample_mem[out_count]);
                    $finish;
                end
                out_count = out_count + 1;
            end
        end

        if (out_count != 5) begin
            $display("FAIL: expected 5 replayed bytes, got %0d", out_count);
            $finish;
        end

        $display("PASS: packet_buffer_tb");
        $finish;
    end
endmodule
