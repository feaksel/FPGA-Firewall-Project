`timescale 1ns/1ps

module w5500_udp_rx_model #(
    parameter PACKET_FILE    = "tb/packets/udp_allow.mem",
    parameter PACKET_LENGTH  = 38,
    parameter PAYLOAD_LENGTH = 0,
    parameter REPEAT_PACKETS = 0
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
    localparam [15:0] COMMON_GAR0       = 16'h0001;
    localparam [15:0] COMMON_GAR1       = 16'h0002;
    localparam [15:0] COMMON_GAR2       = 16'h0003;
    localparam [15:0] COMMON_GAR3       = 16'h0004;
    localparam [15:0] COMMON_SUBR0      = 16'h0005;
    localparam [15:0] COMMON_SUBR1      = 16'h0006;
    localparam [15:0] COMMON_SUBR2      = 16'h0007;
    localparam [15:0] COMMON_SUBR3      = 16'h0008;
    localparam [15:0] COMMON_SHAR0      = 16'h0009;
    localparam [15:0] COMMON_SHAR1      = 16'h000A;
    localparam [15:0] COMMON_SHAR2      = 16'h000B;
    localparam [15:0] COMMON_SHAR3      = 16'h000C;
    localparam [15:0] COMMON_SHAR4      = 16'h000D;
    localparam [15:0] COMMON_SHAR5      = 16'h000E;
    localparam [15:0] COMMON_SIPR0      = 16'h000F;
    localparam [15:0] COMMON_SIPR1      = 16'h0010;
    localparam [15:0] COMMON_SIPR2      = 16'h0011;
    localparam [15:0] COMMON_SIPR3      = 16'h0012;
    localparam [15:0] COMMON_PHYCFGR    = 16'h002E;
    localparam [15:0] COMMON_VERSIONR   = 16'h0039;
    localparam [15:0] S0_MR             = 16'h0000;
    localparam [15:0] S0_CR             = 16'h0001;
    localparam [15:0] S0_SR             = 16'h0003;
    localparam [15:0] S0_PORT0          = 16'h0004;
    localparam [15:0] S0_PORT1          = 16'h0005;
    localparam [15:0] S0_RXBUF_SIZE     = 16'h001E;
    localparam [15:0] S0_TXBUF_SIZE     = 16'h001F;
    localparam [15:0] S0_RX_RSR_MSB     = 16'h0026;
    localparam [15:0] S0_RX_RSR_LSB     = 16'h0027;
    localparam [15:0] S0_RX_RD_MSB      = 16'h0028;
    localparam [15:0] S0_RX_RD_LSB      = 16'h0029;

    localparam [7:0] CTRL_COMMON_READ   = 8'h00;
    localparam [7:0] CTRL_COMMON_WRITE  = 8'h04;
    localparam [7:0] CTRL_S0_REG_READ   = 8'h08;
    localparam [7:0] CTRL_S0_REG_WRITE  = 8'h0C;
    localparam [7:0] CTRL_S0_RXBUF_READ = 8'h18;

    localparam [7:0] W5500_VERSION      = 8'h04;
    localparam [7:0] S0_CR_OPEN         = 8'h01;
    localparam [7:0] S0_CR_RECV         = 8'h40;
    localparam [7:0] S0_STATUS_UDP      = 8'h22;

    reg [7:0] packet_mem [0:PACKET_LENGTH-1];
    reg [7:0] rxbuf_mem [0:2047];

    reg [7:0] common_mr;
    reg [7:0] common_gar [0:3];
    reg [7:0] common_subr [0:3];
    reg [7:0] common_shar [0:5];
    reg [7:0] common_sipr [0:3];
    reg [7:0] s0_mr;
    reg [7:0] s0_sr;
    reg [7:0] s0_port [0:1];
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
    integer    recv_count;

    initial begin
        $readmemh(PACKET_FILE, packet_mem);
    end

    task load_udp_record_at;
        input [15:0] base_addr;
        integer idx;
        begin
            rxbuf_mem[base_addr]          = packet_mem[26];
            rxbuf_mem[base_addr + 16'd1]  = packet_mem[27];
            rxbuf_mem[base_addr + 16'd2]  = packet_mem[28];
            rxbuf_mem[base_addr + 16'd3]  = packet_mem[29];
            rxbuf_mem[base_addr + 16'd4]  = packet_mem[34];
            rxbuf_mem[base_addr + 16'd5]  = packet_mem[35];
            rxbuf_mem[base_addr + 16'd6]  = PAYLOAD_LENGTH[15:8];
            rxbuf_mem[base_addr + 16'd7]  = PAYLOAD_LENGTH[7:0];
            for (idx = 0; idx < PAYLOAD_LENGTH; idx = idx + 1)
                rxbuf_mem[base_addr + 16'd8 + idx[15:0]] = idx[7:0] ^ 8'hA5;
        end
    endtask

    task reset_device;
        begin
            common_mr        = 8'h00;
            for (init_idx = 0; init_idx < 4; init_idx = init_idx + 1) begin
                common_gar[init_idx]  = 8'h00;
                common_subr[init_idx] = 8'h00;
                common_sipr[init_idx] = 8'h00;
            end
            for (init_idx = 0; init_idx < 6; init_idx = init_idx + 1)
                common_shar[init_idx] = 8'h00;
            s0_mr            = 8'h00;
            s0_sr            = 8'h00;
            s0_port[0]       = 8'h00;
            s0_port[1]       = 8'h00;
            s0_rxbuf_size    = 8'h00;
            s0_txbuf_size    = 8'h00;
            s0_rx_rsr        = 16'd8 + PAYLOAD_LENGTH[15:0];
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
            recv_count       = 0;
            load_udp_record_at(16'd0);
        end
    endtask

    function [7:0] read_byte;
        input [15:0] addr;
        input [7:0]  ctrl;
        begin
            read_byte = 8'h00;
            case (ctrl)
                CTRL_COMMON_READ: begin
                    case (addr)
                        COMMON_GAR0:     read_byte = common_gar[0];
                        COMMON_GAR1:     read_byte = common_gar[1];
                        COMMON_GAR2:     read_byte = common_gar[2];
                        COMMON_GAR3:     read_byte = common_gar[3];
                        COMMON_SUBR0:    read_byte = common_subr[0];
                        COMMON_SUBR1:    read_byte = common_subr[1];
                        COMMON_SUBR2:    read_byte = common_subr[2];
                        COMMON_SUBR3:    read_byte = common_subr[3];
                        COMMON_SHAR0:    read_byte = common_shar[0];
                        COMMON_SHAR1:    read_byte = common_shar[1];
                        COMMON_SHAR2:    read_byte = common_shar[2];
                        COMMON_SHAR3:    read_byte = common_shar[3];
                        COMMON_SHAR4:    read_byte = common_shar[4];
                        COMMON_SHAR5:    read_byte = common_shar[5];
                        COMMON_SIPR0:    read_byte = common_sipr[0];
                        COMMON_SIPR1:    read_byte = common_sipr[1];
                        COMMON_SIPR2:    read_byte = common_sipr[2];
                        COMMON_SIPR3:    read_byte = common_sipr[3];
                        COMMON_PHYCFGR:  read_byte = 8'hBF;
                        COMMON_VERSIONR: read_byte = W5500_VERSION;
                        default:         read_byte = 8'h00;
                    endcase
                end

                CTRL_S0_REG_READ: begin
                    case (addr)
                        S0_MR:         read_byte = s0_mr;
                        S0_SR:         read_byte = s0_sr;
                        S0_PORT0:      read_byte = s0_port[0];
                        S0_PORT1:      read_byte = s0_port[1];
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
                    case (addr)
                        COMMON_MR:    common_mr = data;
                        COMMON_GAR0:  common_gar[0] = data;
                        COMMON_GAR1:  common_gar[1] = data;
                        COMMON_GAR2:  common_gar[2] = data;
                        COMMON_GAR3:  common_gar[3] = data;
                        COMMON_SUBR0: common_subr[0] = data;
                        COMMON_SUBR1: common_subr[1] = data;
                        COMMON_SUBR2: common_subr[2] = data;
                        COMMON_SUBR3: common_subr[3] = data;
                        COMMON_SHAR0: common_shar[0] = data;
                        COMMON_SHAR1: common_shar[1] = data;
                        COMMON_SHAR2: common_shar[2] = data;
                        COMMON_SHAR3: common_shar[3] = data;
                        COMMON_SHAR4: common_shar[4] = data;
                        COMMON_SHAR5: common_shar[5] = data;
                        COMMON_SIPR0: common_sipr[0] = data;
                        COMMON_SIPR1: common_sipr[1] = data;
                        COMMON_SIPR2: common_sipr[2] = data;
                        COMMON_SIPR3: common_sipr[3] = data;
                    endcase
                end

                CTRL_S0_REG_WRITE: begin
                    case (addr)
                        S0_MR:         s0_mr         = data;
                        S0_PORT0:      s0_port[0]    = data;
                        S0_PORT1:      s0_port[1]    = data;
                        S0_RXBUF_SIZE: s0_rxbuf_size = data;
                        S0_TXBUF_SIZE: s0_txbuf_size = data;
                        S0_RX_RD_MSB:  s0_rx_rd[15:8]= data;
                        S0_RX_RD_LSB:  s0_rx_rd[7:0] = data;
                        S0_CR: begin
                            if (data == S0_CR_OPEN) begin
                                saw_open_cmd = 1'b1;
                                s0_sr        = S0_STATUS_UDP;
                            end else if (data == S0_CR_RECV) begin
                                saw_recv_cmd = 1'b1;
                                recv_count   = recv_count + 1;
                                if (REPEAT_PACKETS) begin
                                    load_udp_record_at(s0_rx_rd);
                                    s0_rx_rsr = 16'd8 + PAYLOAD_LENGTH[15:0];
                                    int_n     = 1'b0;
                                end else begin
                                    s0_rx_rsr = 16'd0;
                                    int_n     = 1'b1;
                                end
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

                    default: begin
                        if (trans_ctrl == CTRL_S0_RXBUF_READ) begin
                            spi_out_shift = read_byte(trans_addr + (byte_idx - 2), trans_ctrl);
                        end else begin
                            if (byte_idx == 3)
                                write_byte(trans_addr, trans_ctrl, received_byte);
                            spi_out_shift = 8'h00;
                        end
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
