module debug_counters (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        rx_pkt_pulse,
    input  wire        allow_pulse,
    input  wire        drop_pulse,
    output reg [31:0]  rx_count,
    output reg [31:0]  allow_count,
    output reg [31:0]  drop_count
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_count    <= 32'd0;
            allow_count <= 32'd0;
            drop_count  <= 32'd0;
        end else begin
            if (rx_pkt_pulse)
                rx_count <= rx_count + 32'd1;

            if (allow_pulse)
                allow_count <= allow_count + 32'd1;

            if (drop_pulse)
                drop_count <= drop_count + 32'd1;
        end
    end
endmodule
