module spi_master #(
    parameter CLK_DIV = 4,
    parameter CPOL    = 0,
    parameter CPHA    = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [7:0] tx_data,
    output reg  [7:0] rx_data,
    output reg        busy,
    output reg        done,
    output reg        sclk,
    output reg        mosi,
    input  wire       miso,
    output reg        cs_n
);
    reg [15:0] div_ctr;
    reg [2:0]  bit_idx;
    reg        phase;
    reg [7:0]  shreg_tx;
    reg [7:0]  shreg_rx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data  <= 8'd0;
            busy     <= 1'b0;
            done     <= 1'b0;
            sclk     <= CPOL;
            mosi     <= 1'b0;
            cs_n     <= 1'b1;
            div_ctr  <= 16'd0;
            bit_idx  <= 3'd7;
            phase    <= 1'b0;
            shreg_tx <= 8'd0;
            shreg_rx <= 8'd0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                sclk <= CPOL;
                if (start) begin
                    busy     <= 1'b1;
                    cs_n     <= 1'b0;
                    div_ctr  <= 16'd0;
                    bit_idx  <= 3'd7;
                    phase    <= 1'b0;
                    shreg_tx <= tx_data;
                    shreg_rx <= 8'd0;
                    mosi     <= tx_data[7];
                end
            end else begin
                if (div_ctr == (CLK_DIV - 1)) begin
                    div_ctr <= 16'd0;

                    if (phase == 1'b0) begin
                        sclk  <= ~CPOL;
                        phase <= 1'b1;

                        if (CPHA == 0)
                            shreg_rx[bit_idx] <= miso;
                        else
                            mosi <= shreg_tx[bit_idx];
                    end else begin
                        sclk  <= CPOL;
                        phase <= 1'b0;

                        if (CPHA == 0) begin
                            if (bit_idx == 3'd0) begin
                                busy    <= 1'b0;
                                cs_n    <= 1'b1;
                                done    <= 1'b1;
                                rx_data <= shreg_rx;
                            end else begin
                                bit_idx <= bit_idx - 3'd1;
                                mosi    <= shreg_tx[bit_idx - 3'd1];
                            end
                        end else begin
                            shreg_rx[bit_idx] <= miso;
                            if (bit_idx == 3'd0) begin
                                busy    <= 1'b0;
                                cs_n    <= 1'b1;
                                done    <= 1'b1;
                                rx_data <= {shreg_rx[7:1], miso};
                            end else begin
                                bit_idx <= bit_idx - 3'd1;
                            end
                        end
                    end
                end else begin
                    div_ctr <= div_ctr + 16'd1;
                end
            end
        end
    end
endmodule
