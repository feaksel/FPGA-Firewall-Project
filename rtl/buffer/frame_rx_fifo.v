`timescale 1ns/1ps

module frame_rx_fifo #(
    parameter PACKET_DEPTH  = 4,
    parameter MAX_PKT_BYTES = 2048
) (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        in_valid,
    input  wire [7:0]  in_data,
    input  wire        in_sop,
    input  wire        in_eop,
    input  wire [0:0]  in_src_port,
    output wire        in_ready,

    output reg         out_valid,
    output reg  [7:0]  out_data,
    output reg         out_sop,
    output reg         out_eop,
    output reg  [0:0]  out_src_port,
    input  wire        out_ready,

    output reg         overflow_error
);
    localparam TOTAL_BYTES = PACKET_DEPTH * MAX_PKT_BYTES;

    reg [7:0] data_mem [0:TOTAL_BYTES - 1];
    reg       sop_mem  [0:TOTAL_BYTES - 1];
    reg       eop_mem  [0:TOTAL_BYTES - 1];
    reg [0:0] src_mem  [0:TOTAL_BYTES - 1];

    reg [15:0] wr_ptr;
    reg [15:0] rd_ptr;
    reg [15:0] used_count;
    reg [15:0] stored_packet_count;
    reg        write_in_packet;

    wire did_write;
    wire did_read;
    wire read_consumes_packet;
    wire write_completes_packet;

    function [15:0] next_ptr;
        input [15:0] ptr;
        begin
            if (ptr == (TOTAL_BYTES - 1))
                next_ptr = 16'd0;
            else
                next_ptr = ptr + 16'd1;
        end
    endfunction

    assign in_ready = (used_count < TOTAL_BYTES) && (write_in_packet || (stored_packet_count < PACKET_DEPTH));

    assign did_write             = in_valid && in_ready;
    assign did_read              = out_valid && out_ready;
    assign read_consumes_packet  = did_read && out_eop;
    assign write_completes_packet = did_write && in_eop;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr              <= 16'd0;
            rd_ptr              <= 16'd0;
            used_count          <= 16'd0;
            stored_packet_count <= 16'd0;
            write_in_packet     <= 1'b0;
            out_valid           <= 1'b0;
            out_data            <= 8'd0;
            out_sop             <= 1'b0;
            out_eop             <= 1'b0;
            out_src_port        <= 1'b0;
            overflow_error      <= 1'b0;
        end else begin
            if (in_valid && !in_ready)
                overflow_error <= 1'b1;

            if (did_write) begin
                data_mem[wr_ptr] <= in_data;
                sop_mem[wr_ptr]  <= in_sop;
                eop_mem[wr_ptr]  <= in_eop;
                src_mem[wr_ptr]  <= in_src_port;
                wr_ptr           <= next_ptr(wr_ptr);

                if (!write_in_packet) begin
                    if (!in_sop)
                        overflow_error <= 1'b1;
                    write_in_packet <= !in_eop;
                end else begin
                    if (in_sop)
                        overflow_error <= 1'b1;
                    if (in_eop)
                        write_in_packet <= 1'b0;
                end
            end

            used_count          <= used_count + (did_write ? 16'd1 : 16'd0) - (did_read ? 16'd1 : 16'd0);
            stored_packet_count <= stored_packet_count +
                                   (write_completes_packet ? 16'd1 : 16'd0) -
                                   (read_consumes_packet ? 16'd1 : 16'd0);

            if (did_read) begin
                rd_ptr    <= next_ptr(rd_ptr);
                out_valid <= 1'b0;
                out_sop   <= 1'b0;
                out_eop   <= 1'b0;
            end else if (!out_valid && (used_count != 16'd0)) begin
                out_valid    <= 1'b1;
                out_data     <= data_mem[rd_ptr];
                out_sop      <= sop_mem[rd_ptr];
                out_eop      <= eop_mem[rd_ptr];
                out_src_port <= src_mem[rd_ptr];
            end else if (!out_valid) begin
                out_sop <= 1'b0;
                out_eop <= 1'b0;
            end

            if (!out_valid && (used_count == 16'd0) && did_write && !did_read) begin
                out_valid <= 1'b0;
                out_sop   <= 1'b0;
                out_eop   <= 1'b0;
                out_data  <= 8'd0;
            end
        end
    end
endmodule
