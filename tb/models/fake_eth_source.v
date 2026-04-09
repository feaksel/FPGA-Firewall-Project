`timescale 1ns/1ps

module fake_eth_source #(
    parameter MEMORY_FILE = "tb/packets/udp_allow.mem",
    parameter PACKET_LENGTH = 38,
    parameter START_DELAY = 4,
    parameter SRC_PORT_ID = 0
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire       out_ready,
    output reg        out_valid,
    output reg [7:0]  out_data,
    output reg        out_sop,
    output reg        out_eop,
    output reg [0:0]  out_src_port,
    output reg        packet_active,
    output reg        done,
    output reg [15:0] byte_count
);
    reg [7:0] pkt_mem [0:2047];
    reg [15:0] idx;
    reg [15:0] delay_ctr;
    reg        start_seen;

    initial begin
        $readmemh(MEMORY_FILE, pkt_mem);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid     <= 1'b0;
            out_data      <= 8'd0;
            out_sop       <= 1'b0;
            out_eop       <= 1'b0;
            out_src_port  <= SRC_PORT_ID;
            packet_active <= 1'b0;
            done          <= 1'b0;
            byte_count    <= 16'd0;
            idx           <= 16'd0;
            delay_ctr     <= 16'd0;
            start_seen    <= 1'b0;
        end else begin
            out_sop <= 1'b0;
            out_eop <= 1'b0;
            done    <= 1'b0;

            if (start && !start_seen && !packet_active) begin
                start_seen <= 1'b1;
                delay_ctr  <= 16'd0;
            end

            if (start_seen && !packet_active && !out_valid) begin
                if (delay_ctr == START_DELAY) begin
                    packet_active <= 1'b1;
                    out_valid     <= 1'b1;
                    out_data      <= pkt_mem[0];
                    out_sop       <= 1'b1;
                    out_src_port  <= SRC_PORT_ID;
                    idx           <= 16'd0;
                    byte_count    <= 16'd0;
                end else begin
                    delay_ctr <= delay_ctr + 16'd1;
                end
            end else if (packet_active && out_valid && out_ready) begin
                byte_count <= byte_count + 16'd1;
                if (idx == (PACKET_LENGTH - 1)) begin
                    out_eop       <= 1'b1;
                    out_valid     <= 1'b0;
                    packet_active <= 1'b0;
                    done          <= 1'b1;
                    start_seen    <= 1'b0;
                    idx           <= 16'd0;
                end else begin
                    idx      <= idx + 16'd1;
                    out_data <= pkt_mem[idx + 16'd1];
                    out_eop  <= ((idx + 16'd1) == (PACKET_LENGTH - 1));
                end
            end
        end
    end
endmodule
