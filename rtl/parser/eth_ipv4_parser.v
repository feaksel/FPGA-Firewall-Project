`include "defs.vh"

module eth_ipv4_parser (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_eop,

    output reg         hdr_valid,
    output reg         is_ipv4,
    output reg  [7:0]  protocol,
    output reg  [31:0] src_ip,
    output reg  [31:0] dst_ip,
    output reg  [15:0] src_port,
    output reg  [15:0] dst_port,
    output reg         parse_error
);
    reg [7:0]  byte_idx;
    reg [7:0]  current_idx;
    reg [15:0] ethertype;
    reg [7:0]  version_ihl;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            byte_idx    <= 8'd0;
            current_idx <= 8'd0;
            hdr_valid   <= 1'b0;
            is_ipv4     <= 1'b0;
            protocol    <= 8'd0;
            src_ip      <= 32'd0;
            dst_ip      <= 32'd0;
            src_port    <= 16'd0;
            dst_port    <= 16'd0;
            parse_error <= 1'b0;
            ethertype   <= 16'd0;
            version_ihl <= 8'd0;
        end else begin
            hdr_valid   <= 1'b0;
            parse_error <= 1'b0;

            if (in_valid) begin
                current_idx = in_sop ? 8'd0 : (byte_idx + 8'd1);
                byte_idx    <= current_idx;

                if (in_sop) begin
                    is_ipv4     <= 1'b0;
                    protocol    <= 8'd0;
                    src_ip      <= 32'd0;
                    dst_ip      <= 32'd0;
                    src_port    <= 16'd0;
                    dst_port    <= 16'd0;
                    ethertype   <= 16'd0;
                    version_ihl <= 8'd0;
                end

                case (current_idx)
                    8'd12: ethertype[15:8] <= in_data;
                    8'd13: begin
                        ethertype[7:0] <= in_data;
                        is_ipv4 <= ({ethertype[15:8], in_data} == 16'h0800);
                    end
                    8'd14: version_ihl <= in_data;
                    8'd23: protocol <= in_data;
                    8'd26: src_ip[31:24] <= in_data;
                    8'd27: src_ip[23:16] <= in_data;
                    8'd28: src_ip[15:8]  <= in_data;
                    8'd29: src_ip[7:0]   <= in_data;
                    8'd30: dst_ip[31:24] <= in_data;
                    8'd31: dst_ip[23:16] <= in_data;
                    8'd32: dst_ip[15:8]  <= in_data;
                    8'd33: dst_ip[7:0]   <= in_data;
                    8'd34: src_port[15:8] <= in_data;
                    8'd35: src_port[7:0]  <= in_data;
                    8'd36: dst_port[15:8] <= in_data;
                    8'd37: begin
                        dst_port[7:0] <= in_data;
                        if (is_ipv4 &&
                            (version_ihl == 8'h45) &&
                            ((protocol == `PROTO_TCP) || (protocol == `PROTO_UDP))) begin
                            hdr_valid <= 1'b1;
                        end else begin
                            parse_error <= 1'b1;
                        end
                    end
                endcase

                if (in_eop && (current_idx < 8'd37))
                    parse_error <= 1'b1;
            end
        end
    end
endmodule
