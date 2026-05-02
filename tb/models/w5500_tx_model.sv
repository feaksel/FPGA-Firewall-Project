`timescale 1ns/1ps

module w5500_tx_model #(
    parameter TXBUF_BYTES = 2048
) (
    input  wire rst_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n,
    output reg  saw_send_cmd,
    output reg [15:0] tx_frame_len,
    output reg [31:0] tx_send_count
);
    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_TX_FSR_MSB     = 16'h0020;
    localparam [15:0] S0_TX_FSR_LSB     = 16'h0021;
    localparam [15:0] S0_TX_WR_MSB      = 16'h0024;
    localparam [15:0] S0_TX_WR_LSB      = 16'h0025;

    localparam [7:0] CTRL_S0_REG_READ   = 8'h08;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h0C;
    localparam [7:0] CTRL_S0_TXBUF_WRITE= 8'h14;

    localparam [7:0] S0_CR_SEND         = 8'h20;

    reg [7:0] txbuf_mem [0:TXBUF_BYTES-1];
    reg [7:0] sent_mem [0:TXBUF_BYTES-1];
    reg [15:0] s0_tx_fsr;
    reg [15:0] s0_tx_wr;
    reg [15:0] last_send_start;

    reg [15:0] trans_addr;
    reg [7:0]  trans_ctrl;
    reg [7:0]  spi_in_shift;
    reg [7:0]  spi_out_shift;
    reg [7:0]  received_byte;
    integer    bit_idx;
    integer    byte_idx;
    integer    idx;

    task reset_device;
        begin
            s0_tx_fsr     = TXBUF_BYTES;
            s0_tx_wr      = 16'd0;
            last_send_start = 16'd0;
            saw_send_cmd  = 1'b0;
            tx_frame_len  = 16'd0;
            tx_send_count = 32'd0;
            miso          = 1'b0;
            spi_in_shift  = 8'd0;
            spi_out_shift = 8'd0;
            trans_addr    = 16'd0;
            trans_ctrl    = 8'd0;
            bit_idx       = 7;
            byte_idx      = 0;
            for (idx = 0; idx < TXBUF_BYTES; idx = idx + 1) begin
                txbuf_mem[idx] = 8'h00;
                sent_mem[idx]  = 8'h00;
            end
        end
    endtask

    function [7:0] read_byte;
        input [15:0] addr;
        input [7:0]  ctrl;
        begin
            read_byte = 8'h00;
            if (ctrl == CTRL_S0_REG_READ) begin
                case (addr)
                    S0_TX_FSR_MSB: read_byte = s0_tx_fsr[15:8];
                    S0_TX_FSR_LSB: read_byte = s0_tx_fsr[7:0];
                    S0_TX_WR_MSB:  read_byte = s0_tx_wr[15:8];
                    S0_TX_WR_LSB:  read_byte = s0_tx_wr[7:0];
                    default:       read_byte = 8'h00;
                endcase
            end
        end
    endfunction

    task capture_send;
        integer n;
        begin
            tx_frame_len = s0_tx_wr - last_send_start;
            for (n = 0; n < tx_frame_len; n = n + 1)
                sent_mem[n] = txbuf_mem[last_send_start + n];
            last_send_start = s0_tx_wr;
            tx_send_count   = tx_send_count + 32'd1;
            saw_send_cmd    = 1'b1;
        end
    endtask

    task write_byte;
        input [15:0] addr;
        input [7:0]  ctrl;
        input [7:0]  data;
        begin
            case (ctrl)
                CTRL_S0_REG_WRITE: begin
                    case (addr)
                        S0_TX_WR_MSB: s0_tx_wr[15:8] = data;
                        S0_TX_WR_LSB: s0_tx_wr[7:0]  = data;
                        S0_CR: begin
                            if (data == S0_CR_SEND)
                                capture_send();
                        end
                    endcase
                end

                CTRL_S0_TXBUF_WRITE: begin
                    txbuf_mem[addr] = data;
                end
            endcase
        end
    endtask

    always @(negedge rst_n) begin
        reset_device();
    end

    initial begin
        reset_device();
    end

    always @(negedge cs_n) begin
        bit_idx       = 7;
        byte_idx      = 0;
        spi_in_shift  = 8'd0;
        spi_out_shift = 8'd0;
        miso          = 1'b0;
    end

    always @(posedge sclk) begin
        if (!cs_n) begin
            spi_in_shift[bit_idx] = mosi;
            if (bit_idx == 0) begin
                received_byte = spi_in_shift;
                case (byte_idx)
                    0: begin
                        trans_addr[15:8] = received_byte;
                        spi_out_shift    = 8'h00;
                    end

                    1: begin
                        trans_addr[7:0] = received_byte;
                        spi_out_shift   = 8'h00;
                    end

                    2: begin
                        trans_ctrl    = received_byte;
                        spi_out_shift = read_byte(trans_addr, received_byte);
                    end

                    default: begin
                        write_byte(trans_addr + (byte_idx - 3), trans_ctrl, received_byte);
                        spi_out_shift = 8'h00;
                    end
                endcase

                byte_idx = byte_idx + 1;
                bit_idx  = 7;
            end else begin
                bit_idx = bit_idx - 1;
            end
        end
    end

    always @(negedge sclk) begin
        if (!cs_n) begin
            miso          = spi_out_shift[7];
            spi_out_shift = {spi_out_shift[6:0], 1'b0};
        end
    end

    task automatic expect_sent_byte;
        input integer byte_index;
        input [7:0] expected;
        begin
            if (sent_mem[byte_index] !== expected) begin
                $error("sent byte %0d mismatch: got 0x%02h expected 0x%02h",
                       byte_index, sent_mem[byte_index], expected);
                $fatal(1);
            end
        end
    endtask
endmodule
