module packet_buffer #(
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

    input  wire        rd_start,
    output reg         out_valid,
    output reg [7:0]   out_data,
    output reg         out_sop,
    output reg         out_eop,
    output reg [0:0]   out_src_port,
    input  wire        out_ready,

    output reg [15:0]  pkt_len,
    output reg         pkt_done,
    output reg         pkt_available,
    output reg         overflow_error
);
    reg [7:0] mem [0:MAX_PKT_BYTES-1];
    reg [15:0] wr_ptr;
    reg [15:0] rd_ptr;
    reg [0:0]  stored_src_port;
    reg        rd_active;

    assign in_ready = !pkt_available && (wr_ptr < MAX_PKT_BYTES);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr          <= 16'd0;
            rd_ptr          <= 16'd0;
            rd_active       <= 1'b0;
            pkt_len         <= 16'd0;
            pkt_done        <= 1'b0;
            pkt_available   <= 1'b0;
            overflow_error  <= 1'b0;
            out_valid       <= 1'b0;
            out_data        <= 8'd0;
            out_sop         <= 1'b0;
            out_eop         <= 1'b0;
            out_src_port    <= 1'b0;
            stored_src_port <= 1'b0;
        end else begin
            pkt_done <= 1'b0;
            out_sop  <= 1'b0;
            out_eop  <= 1'b0;

            if (in_valid && in_ready) begin
                if (in_sop)
                    wr_ptr <= 16'd0;

                mem[in_sop ? 16'd0 : wr_ptr] <= in_data;

                if (in_sop)
                    stored_src_port <= in_src_port;

                if (in_eop) begin
                    pkt_len       <= (in_sop ? 16'd1 : (wr_ptr + 16'd1));
                    pkt_done      <= 1'b1;
                    pkt_available <= 1'b1;
                    wr_ptr        <= 16'd0;
                end else begin
                    wr_ptr <= (in_sop ? 16'd1 : (wr_ptr + 16'd1));
                end
            end else if (in_valid && !in_ready) begin
                overflow_error <= 1'b1;
            end

            if (rd_start && pkt_available && !rd_active) begin
                rd_active    <= 1'b1;
                rd_ptr       <= 16'd0;
                out_valid    <= 1'b1;
                out_data     <= mem[0];
                out_sop      <= 1'b1;
                out_eop      <= (pkt_len == 16'd1);
                out_src_port <= stored_src_port;
            end else if (rd_active && out_valid && out_ready) begin
                if (rd_ptr == (pkt_len - 16'd1)) begin
                    rd_active     <= 1'b0;
                    out_valid     <= 1'b0;
                    pkt_available <= 1'b0;
                    rd_ptr        <= 16'd0;
                end else begin
                    rd_ptr       <= rd_ptr + 16'd1;
                    out_data     <= mem[rd_ptr + 16'd1];
                    out_sop      <= 1'b0;
                    out_eop      <= ((rd_ptr + 16'd1) == (pkt_len - 16'd1));
                    out_src_port <= stored_src_port;
                end
            end
        end
    end
endmodule
