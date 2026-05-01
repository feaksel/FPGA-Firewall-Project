`timescale 1ns/1ps

module seven_seg_hex_tb;
    logic [3:0] value;
    logic       blank;
    logic [6:0] segments_n;

    seven_seg_hex dut (
        .value(value),
        .blank(blank),
        .segments_n(segments_n)
    );

    task automatic expect_segments(input [3:0] v, input [6:0] expected);
        begin
            value = v;
            blank = 1'b0;
            #1;
            if (segments_n !== expected) begin
                $display("FAIL: value=%h expected=%b actual=%b", v, expected, segments_n);
                $finish;
            end
        end
    endtask

    initial begin
        blank = 1'b1;
        value = 4'h0;
        #1;
        if (segments_n !== 7'b1111111) begin
            $display("FAIL: blank expected=1111111 actual=%b", segments_n);
            $finish;
        end

        expect_segments(4'h0, 7'b1000000);
        expect_segments(4'h1, 7'b1111001);
        expect_segments(4'h2, 7'b0100100);
        expect_segments(4'h3, 7'b0110000);
        expect_segments(4'h4, 7'b0011001);
        expect_segments(4'h5, 7'b0010010);
        expect_segments(4'h6, 7'b0000010);
        expect_segments(4'h7, 7'b1111000);
        expect_segments(4'h8, 7'b0000000);
        expect_segments(4'h9, 7'b0010000);
        expect_segments(4'hA, 7'b0001000);
        expect_segments(4'hB, 7'b0000011);
        expect_segments(4'hC, 7'b1000110);
        expect_segments(4'hD, 7'b0100001);
        expect_segments(4'hE, 7'b0000110);
        expect_segments(4'hF, 7'b0001110);

        $display("PASS: seven_seg_hex_tb");
        $finish;
    end
endmodule
