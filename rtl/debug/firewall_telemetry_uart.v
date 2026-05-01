`timescale 1ns/1ps

module firewall_telemetry_uart #(
    parameter CLKS_PER_BIT = 434,
    parameter REPORT_INTERVAL_CYCLES = 25_000_000
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] rx_count,
    input  wire [31:0] allow_count,
    input  wire [31:0] drop_count,
    input  wire [3:0]  last_rule_id,
    input  wire        last_action_allow,
    input  wire        tx_error,
    output wire        uart_tx
);
    localparam MSG_LEN = 42;

    reg [31:0] interval_count;
    reg        sending;
    reg [5:0]  char_index;
    reg        tx_valid;
    reg [7:0]  tx_data;
    wire       tx_ready;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk),
        .rst_n(rst_n),
        .in_valid(tx_valid),
        .in_data(tx_data),
        .in_ready(tx_ready),
        .tx(uart_tx)
    );

    function [7:0] hex_digit;
        input [3:0] value;
        begin
            hex_digit = (value < 4'd10) ? (8'h30 + value) : (8'h41 + value - 4'd10);
        end
    endfunction

    function [7:0] hex32_char;
        input [31:0] value;
        input [2:0]  nibble_index;
        begin
            case (nibble_index)
                3'd0: hex32_char = hex_digit(value[31:28]);
                3'd1: hex32_char = hex_digit(value[27:24]);
                3'd2: hex32_char = hex_digit(value[23:20]);
                3'd3: hex32_char = hex_digit(value[19:16]);
                3'd4: hex32_char = hex_digit(value[15:12]);
                3'd5: hex32_char = hex_digit(value[11:8]);
                3'd6: hex32_char = hex_digit(value[7:4]);
                default: hex32_char = hex_digit(value[3:0]);
            endcase
        end
    endfunction

    function [7:0] message_char;
        input [5:0] index;
        begin
            case (index)
                6'd0:  message_char = "R";
                6'd1:  message_char = "X";
                6'd2:  message_char = "=";
                6'd3:  message_char = hex32_char(rx_count, 3'd0);
                6'd4:  message_char = hex32_char(rx_count, 3'd1);
                6'd5:  message_char = hex32_char(rx_count, 3'd2);
                6'd6:  message_char = hex32_char(rx_count, 3'd3);
                6'd7:  message_char = hex32_char(rx_count, 3'd4);
                6'd8:  message_char = hex32_char(rx_count, 3'd5);
                6'd9:  message_char = hex32_char(rx_count, 3'd6);
                6'd10: message_char = hex32_char(rx_count, 3'd7);
                6'd11: message_char = " ";
                6'd12: message_char = "A";
                6'd13: message_char = "L";
                6'd14: message_char = "=";
                6'd15: message_char = hex32_char(allow_count, 3'd0);
                6'd16: message_char = hex32_char(allow_count, 3'd1);
                6'd17: message_char = hex32_char(allow_count, 3'd2);
                6'd18: message_char = hex32_char(allow_count, 3'd3);
                6'd19: message_char = hex32_char(allow_count, 3'd4);
                6'd20: message_char = hex32_char(allow_count, 3'd5);
                6'd21: message_char = hex32_char(allow_count, 3'd6);
                6'd22: message_char = hex32_char(allow_count, 3'd7);
                6'd23: message_char = " ";
                6'd24: message_char = "D";
                6'd25: message_char = "R";
                6'd26: message_char = "=";
                6'd27: message_char = hex32_char(drop_count, 3'd0);
                6'd28: message_char = hex32_char(drop_count, 3'd1);
                6'd29: message_char = hex32_char(drop_count, 3'd2);
                6'd30: message_char = hex32_char(drop_count, 3'd3);
                6'd31: message_char = hex32_char(drop_count, 3'd4);
                6'd32: message_char = hex32_char(drop_count, 3'd5);
                6'd33: message_char = hex32_char(drop_count, 3'd6);
                6'd34: message_char = hex32_char(drop_count, 3'd7);
                6'd35: message_char = " ";
                6'd36: message_char = "R";
                6'd37: message_char = hex_digit(last_rule_id);
                6'd38: message_char = last_action_allow ? "A" : "D";
                6'd39: message_char = tx_error ? "E" : ".";
                6'd40: message_char = 8'h0D;
                default: message_char = 8'h0A;
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            interval_count <= 32'd0;
            sending        <= 1'b0;
            char_index     <= 6'd0;
            tx_valid       <= 1'b0;
            tx_data        <= 8'd0;
        end else begin
            tx_valid <= 1'b0;

            if (!sending) begin
                if (interval_count == (REPORT_INTERVAL_CYCLES - 1)) begin
                    interval_count <= 32'd0;
                    sending        <= 1'b1;
                    char_index     <= 6'd0;
                end else begin
                    interval_count <= interval_count + 32'd1;
                end
            end else if (tx_ready) begin
                tx_valid <= 1'b1;
                tx_data  <= message_char(char_index);
                if (char_index == (MSG_LEN - 1)) begin
                    sending    <= 1'b0;
                    char_index <= 6'd0;
                end else begin
                    char_index <= char_index + 6'd1;
                end
            end
        end
    end
endmodule
