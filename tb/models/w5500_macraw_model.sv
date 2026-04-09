`timescale 1ns/1ps

module w5500_macraw_model #(
    parameter PACKET_FILE   = "tb/packets/udp_allow.mem",
    parameter PACKET_LENGTH = 38
) (
    input  wire rst_n,
    input  wire w5500_reset_n,
    input  wire sclk,
    input  wire mosi,
    output reg  miso,
    input  wire cs_n,
    output reg  int_n,
    output reg  saw_version_read,
    output reg  saw_open_cmd,
    output reg  saw_recv_cmd
);
    localparam [15:0] COMMON_MR         = 16'h0000;
    localparam [15:0] COMMON_VERSIONR   = 16'h0039;
    localparam [15:0] S0_MR             = 16'h0000;
    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_SR             = 16'h0003;
    localparam [15:0] S0_RXBUF_SIZE     = 16'h001E;
    localparam [15:0] S0_TXBUF_SIZE     = 16'h001F;
    localparam [15:0] S0_RX_RSR_MSB     = 16'h0026;
    localparam [15:0] S0_RX_RSR_LSB     = 16'h0027;
    localparam [15:0] S0_RX_RD_MSB      = 16'h0028;
    localparam [15:0] S0_RX_RD_LSB      = 16'h0029;

    localparam [7:0] CTRL_COMMON_WRITE  = 8'h00;
    localparam [7:0] CTRL_COMMON_READ   = 8'h04;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h08;
    localparam [7:0] CTRL_S0_REG_READ   = 8'h0C;
    localparam [7:0] CTRL_S0_RXBUF_READ = 8'h1C;

    localparam [7:0] W5500_VERSION      = 8'h04;
    localparam [7:0] S0_CR_OPEN         = 8'h01;
    localparam [7:0] S0_CR_RECV         = 8'h40;
    localparam [7:0] S0_STATUS_MACRAW   = 8'h42;

    reg [7:0] packet_mem [0:PACKET_LENGTH-1];
    reg [7:0] rxbuf_mem [0:2047];

    reg [7:0] common_mr;
    reg [7:0] s0_mr;
    reg [7:0] s0_sr;
    reg [7:0] s0_rxbuf_size;
    reg [7:0] s0_txbuf_size;
    reg [15:0] s0_rx_rsr;
    reg [15:0] s0_rx_rd;

    reg [15:0] trans_addr;
    reg [7:0]  trans_ctrl;
    reg [7:0]  spi_in_shift;
    reg [7:0]  spi_out_shift;
    reg [7:0]  received_byte;
    integer    bit_idx;
    integer    byte_idx;
    integer    init_idx;

    initial begin
        $readmemh(PACKET_FILE, packet_mem);
    end

    task reset_device;
        integer idx;
        begin
            common_mr        = 8'h00;
            s0_mr            = 8'h00;
            s0_sr            = 8'h00;
            s0_rxbuf_size    = 8'h00;
            s0_txbuf_size    = 8'h00;
            s0_rx_rsr        = PACKET_LENGTH + 16'd2;
            s0_rx_rd         = 16'd0;
            int_n            = 1'b0;
            saw_version_read = 1'b0;
            saw_open_cmd     = 1'b0;
            saw_recv_cmd     = 1'b0;
            miso             = 1'b0;
            spi_in_shift     = 8'd0;
            spi_out_shift    = 8'd0;
            trans_addr       = 16'd0;
            trans_ctrl       = 8'd0;
            bit_idx          = 7;
            byte_idx         = 0;
            rxbuf_mem[0]     = PACKET_LENGTH[15:8];
            rxbuf_mem[1]     = PACKET_LENGTH[7:0];
            for (idx = 0; idx < PACKET_LENGTH; idx = idx + 1)
                rxbuf_mem[idx + 2] = packet_mem[idx];
        end
    endtask

    function [7:0] read_byte;
        input [15:0] addr;
        input [7:0]  ctrl;
        begin
            read_byte = 8'h00;
            case (ctrl)
                CTRL_COMMON_READ: begin
                    if (addr == COMMON_VERSIONR)
                        read_byte = W5500_VERSION;
                end

                CTRL_S0_REG_READ: begin
                    case (addr)
                        S0_MR:         read_byte = s0_mr;
                        S0_SR:         read_byte = s0_sr;
                        S0_RXBUF_SIZE: read_byte = s0_rxbuf_size;
                        S0_TXBUF_SIZE: read_byte = s0_txbuf_size;
                        S0_RX_RSR_MSB: read_byte = s0_rx_rsr[15:8];
                        S0_RX_RSR_LSB: read_byte = s0_rx_rsr[7:0];
                        S0_RX_RD_MSB:  read_byte = s0_rx_rd[15:8];
                        S0_RX_RD_LSB:  read_byte = s0_rx_rd[7:0];
                        default:       read_byte = 8'h00;
                    endcase
                end

                CTRL_S0_RXBUF_READ: begin
                    read_byte = rxbuf_mem[addr];
                end
            endcase
        end
    endfunction

    task write_byte;
        input [15:0] addr;
        input [7:0]  ctrl;
        input [7:0]  data;
        begin
            case (ctrl)
                CTRL_COMMON_WRITE: begin
                    if (addr == COMMON_MR)
                        common_mr = data;
                end

                CTRL_S0_REG_WRITE: begin
                    case (addr)
                        S0_MR:         s0_mr         = data;
                        S0_RXBUF_SIZE: s0_rxbuf_size = data;
                        S0_TXBUF_SIZE: s0_txbuf_size = data;
                        S0_RX_RD_MSB:  s0_rx_rd[15:8]= data;
                        S0_RX_RD_LSB:  s0_rx_rd[7:0] = data;
                        S0_CR: begin
                            if (data == S0_CR_OPEN) begin
                                saw_open_cmd = 1'b1;
                                s0_sr        = S0_STATUS_MACRAW;
                            end else if (data == S0_CR_RECV) begin
                                saw_recv_cmd = 1'b1;
                                s0_rx_rsr    = 16'd0;
                                int_n        = 1'b1;
                            end
                        end
                    endcase
                end
            endcase
        end
    endtask

    always @(negedge rst_n or negedge w5500_reset_n) begin
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
                        trans_ctrl = received_byte;
                        if ((trans_ctrl == CTRL_COMMON_READ) && (trans_addr == COMMON_VERSIONR))
                            saw_version_read = 1'b1;
                        spi_out_shift = read_byte(trans_addr, received_byte);
                    end

                    3: begin
                        write_byte(trans_addr, trans_ctrl, received_byte);
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
endmodule
