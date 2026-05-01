`timescale 1ns/1ps

module uart_tx #(
    parameter CLKS_PER_BIT = 434
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       in_valid,
    input  wire [7:0] in_data,
    output reg        in_ready,
    output reg        tx
);
    localparam ST_IDLE  = 2'd0;
    localparam ST_START = 2'd1;
    localparam ST_DATA  = 2'd2;
    localparam ST_STOP  = 2'd3;

    reg [1:0]  state;
    reg [15:0] clk_count;
    reg [2:0]  bit_index;
    reg [7:0]  shifter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= ST_IDLE;
            clk_count <= 16'd0;
            bit_index <= 3'd0;
            shifter   <= 8'd0;
            in_ready  <= 1'b1;
            tx        <= 1'b1;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx        <= 1'b1;
                    in_ready  <= 1'b1;
                    clk_count <= 16'd0;
                    bit_index <= 3'd0;
                    if (in_valid) begin
                        shifter  <= in_data;
                        in_ready <= 1'b0;
                        tx       <= 1'b0;
                        state    <= ST_START;
                    end
                end

                ST_START: begin
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        tx        <= shifter[0];
                        state     <= ST_DATA;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_DATA: begin
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        if (bit_index == 3'd7) begin
                            bit_index <= 3'd0;
                            tx        <= 1'b1;
                            state     <= ST_STOP;
                        end else begin
                            bit_index <= bit_index + 3'd1;
                            tx        <= shifter[bit_index + 3'd1];
                        end
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end

                ST_STOP: begin
                    if (clk_count == (CLKS_PER_BIT - 1)) begin
                        clk_count <= 16'd0;
                        state     <= ST_IDLE;
                    end else begin
                        clk_count <= clk_count + 16'd1;
                    end
                end
            endcase
        end
    end
endmodule
