`timescale 1ns/1ps

module frame_rx_fifo_tb;
    import fw_tb_pkg::*;

    logic clk;
    logic rst_n;
    logic in_valid;
    logic [7:0] in_data;
    logic in_sop;
    logic in_eop;
    logic [0:0] in_src_port;
    logic in_ready;
    logic out_valid;
    logic [7:0] out_data;
    logic out_sop;
    logic out_eop;
    logic [0:0] out_src_port;
    logic out_ready;
    logic overflow_error;

    logic [7:0] pkt_a [0:2];
    logic [7:0] pkt_b [0:1];
    logic [7:0] pkt_c [0:3];
    logic [7:0] pkt_d0 [0:0];
    logic [7:0] pkt_d1 [0:0];
    logic [7:0] pkt_d2 [0:0];
    logic [7:0] pkt_d3 [0:0];
    logic [7:0] pkt_d4 [0:0];

    frame_rx_fifo #(
        .PACKET_DEPTH(4),
        .MAX_PKT_BYTES(16)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(in_valid),
        .in_data(in_data),
        .in_sop(in_sop),
        .in_eop(in_eop),
        .in_src_port(in_src_port),
        .in_ready(in_ready),
        .out_valid(out_valid),
        .out_data(out_data),
        .out_sop(out_sop),
        .out_eop(out_eop),
        .out_src_port(out_src_port),
        .out_ready(out_ready),
        .overflow_error(overflow_error)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    task automatic clear_input;
        begin
            in_valid    = 1'b0;
            in_data     = 8'd0;
            in_sop      = 1'b0;
            in_eop      = 1'b0;
            in_src_port = 1'b0;
        end
    endtask

    task automatic reset_dut;
        begin
            rst_n     = 1'b0;
            out_ready = 1'b0;
            clear_input();
            repeat (4) @(negedge clk);
            rst_n = 1'b1;
            repeat (4) @(negedge clk);
        end
    endtask

    task automatic drive_packet(
        input int         packet_len,
        input logic [7:0] pkt_mem [],
        input logic       src_port
    );
        int idx;
        begin
            for (idx = 0; idx < packet_len; idx++) begin
                while (!in_ready)
                    @(negedge clk);

                @(negedge clk);
                in_valid    = 1'b1;
                in_data     = pkt_mem[idx];
                in_sop      = (idx == 0);
                in_eop      = (idx == (packet_len - 1));
                in_src_port = src_port;
            end

            @(negedge clk);
            clear_input();
        end
    endtask

    task automatic expect_held_output(
        input logic [7:0] expected_data,
        input logic       expected_sop,
        input logic       expected_eop,
        input logic       expected_src_port,
        input integer     cycles
    );
        integer idx;
        begin
            for (idx = 0; idx < cycles; idx++) begin
                while (!out_valid)
                    @(negedge clk);
                @(negedge clk);
                expect_u8("fifo.held.data", out_data, expected_data);
                expect_bit("fifo.held.sop", out_sop, expected_sop);
                expect_bit("fifo.held.eop", out_eop, expected_eop);
                expect_bit("fifo.held.src", out_src_port, expected_src_port);
                @(posedge clk);
            end
        end
    endtask

    task automatic consume_beat(
        input logic [7:0] expected_data,
        input logic       expected_sop,
        input logic       expected_eop,
        input logic       expected_src_port
    );
        begin
            while (!out_valid)
                @(negedge clk);
            out_ready = 1'b0;
            @(negedge clk);
            expect_u8("fifo.beat.data", out_data, expected_data);
            expect_bit("fifo.beat.sop", out_sop, expected_sop);
            expect_bit("fifo.beat.eop", out_eop, expected_eop);
            expect_bit("fifo.beat.src", out_src_port, expected_src_port);
            out_ready = 1'b1;
            @(posedge clk);
            out_ready = 1'b0;
            @(negedge clk);
        end
    endtask

    initial begin
        pkt_a[0] = 8'hA1; pkt_a[1] = 8'hA2; pkt_a[2] = 8'hA3;
        pkt_b[0] = 8'hB1; pkt_b[1] = 8'hB2;
        pkt_c[0] = 8'hC1; pkt_c[1] = 8'hC2; pkt_c[2] = 8'hC3; pkt_c[3] = 8'hC4;
        pkt_d0[0] = 8'hD1;
        pkt_d1[0] = 8'hD2;
        pkt_d2[0] = 8'hD3;
        pkt_d3[0] = 8'hD4;
        pkt_d4[0] = 8'hE1;
    end

    initial begin
        reset_dut();

        out_ready = 1'b0;
        drive_packet(3, pkt_a, 1'b0);
        expect_held_output(8'hA1, 1'b1, 1'b0, 1'b0, 3);

        consume_beat(8'hA1, 1'b1, 1'b0, 1'b0);
        consume_beat(8'hA2, 1'b0, 1'b0, 1'b0);
        consume_beat(8'hA3, 1'b0, 1'b1, 1'b0);

        reset_dut();

        out_ready = 1'b0;
        drive_packet(2, pkt_b, 1'b1);
        drive_packet(4, pkt_c, 1'b0);
        consume_beat(8'hB1, 1'b1, 1'b0, 1'b1);
        consume_beat(8'hB2, 1'b0, 1'b1, 1'b1);
        consume_beat(8'hC1, 1'b1, 1'b0, 1'b0);
        consume_beat(8'hC2, 1'b0, 1'b0, 1'b0);
        consume_beat(8'hC3, 1'b0, 1'b0, 1'b0);
        consume_beat(8'hC4, 1'b0, 1'b1, 1'b0);

        reset_dut();

        out_ready = 1'b0;
        drive_packet(1, pkt_d0, 1'b0);
        drive_packet(1, pkt_d1, 1'b1);
        drive_packet(1, pkt_d2, 1'b0);
        drive_packet(1, pkt_d3, 1'b1);

        @(negedge clk);
        expect_bit("fifo.full.in_ready", in_ready, 1'b0);

        @(negedge clk);
        in_valid    = 1'b1;
        in_data     = pkt_d4[0];
        in_sop      = 1'b1;
        in_eop      = 1'b1;
        in_src_port = 1'b0;
        @(negedge clk);
        expect_bit("fifo.overflow_error", overflow_error, 1'b1);
        @(negedge clk);
        clear_input();

        consume_beat(8'hD1, 1'b1, 1'b1, 1'b0);
        consume_beat(8'hD2, 1'b1, 1'b1, 1'b1);
        consume_beat(8'hD3, 1'b1, 1'b1, 1'b0);
        consume_beat(8'hD4, 1'b1, 1'b1, 1'b1);

        $display("PASS: frame_rx_fifo_tb");
        $finish;
    end
endmodule
