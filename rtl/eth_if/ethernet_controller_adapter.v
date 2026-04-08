module ethernet_controller_adapter #(
    parameter STARTUP_WAIT_CYCLES = 16,
    parameter SPI_CLK_DIV         = 4
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start_init,

    output wire        spi_sclk,
    output wire        spi_mosi,
    input  wire        spi_miso,
    output wire        spi_cs_n,

    output reg         init_busy,
    output reg         init_done,
    output reg         init_error,

    output reg         frame_valid,
    output reg [7:0]   frame_data,
    output reg         frame_sop,
    output reg         frame_eop,
    output reg [0:0]   frame_src_port,
    input  wire        frame_ready,

    output reg [3:0]   debug_state
);
    localparam ST_IDLE       = 4'd0;
    localparam ST_WAIT       = 4'd1;
    localparam ST_SEND_CMD0  = 4'd2;
    localparam ST_WAIT_CMD0  = 4'd3;
    localparam ST_SEND_DATA0 = 4'd4;
    localparam ST_WAIT_DATA0 = 4'd5;
    localparam ST_SEND_CMD1  = 4'd6;
    localparam ST_WAIT_CMD1  = 4'd7;
    localparam ST_SEND_DATA1 = 4'd8;
    localparam ST_WAIT_DATA1 = 4'd9;
    localparam ST_READY      = 4'd10;

    reg [3:0]  state;
    reg [15:0] wait_ctr;
    reg        spi_start;
    reg [7:0]  spi_tx_data;
    wire [7:0] spi_rx_data;
    wire       spi_busy;
    wire       spi_done;

    spi_master #(
        .CLK_DIV(SPI_CLK_DIV),
        .CPOL(0),
        .CPHA(0)
    ) u_spi_master (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .tx_data(spi_tx_data),
        .rx_data(spi_rx_data),
        .busy(spi_busy),
        .done(spi_done),
        .sclk(spi_sclk),
        .mosi(spi_mosi),
        .miso(spi_miso),
        .cs_n(spi_cs_n)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= ST_IDLE;
            wait_ctr       <= 16'd0;
            spi_start      <= 1'b0;
            spi_tx_data    <= 8'd0;
            init_busy      <= 1'b0;
            init_done      <= 1'b0;
            init_error     <= 1'b0;
            frame_valid    <= 1'b0;
            frame_data     <= 8'd0;
            frame_sop      <= 1'b0;
            frame_eop      <= 1'b0;
            frame_src_port <= 1'b0;
            debug_state    <= ST_IDLE;
        end else begin
            spi_start   <= 1'b0;
            frame_valid <= 1'b0;
            frame_sop   <= 1'b0;
            frame_eop   <= 1'b0;
            debug_state <= state;

            case (state)
                ST_IDLE: begin
                    init_busy <= 1'b0;
                    init_done <= 1'b0;
                    if (start_init) begin
                        init_busy <= 1'b1;
                        wait_ctr  <= 16'd0;
                        state     <= ST_WAIT;
                    end
                end

                ST_WAIT: begin
                    if (wait_ctr == STARTUP_WAIT_CYCLES - 1)
                        state <= ST_SEND_CMD0;
                    else
                        wait_ctr <= wait_ctr + 16'd1;
                end

                ST_SEND_CMD0: begin
                    spi_tx_data <= 8'hAA;
                    spi_start   <= 1'b1;
                    state       <= ST_WAIT_CMD0;
                end

                ST_WAIT_CMD0: begin
                    if (spi_done)
                        state <= ST_SEND_DATA0;
                end

                ST_SEND_DATA0: begin
                    spi_tx_data <= 8'h55;
                    spi_start   <= 1'b1;
                    state       <= ST_WAIT_DATA0;
                end

                ST_WAIT_DATA0: begin
                    if (spi_done)
                        state <= ST_SEND_CMD1;
                end

                ST_SEND_CMD1: begin
                    spi_tx_data <= 8'h0F;
                    spi_start   <= 1'b1;
                    state       <= ST_WAIT_CMD1;
                end

                ST_WAIT_CMD1: begin
                    if (spi_done)
                        state <= ST_SEND_DATA1;
                end

                ST_SEND_DATA1: begin
                    spi_tx_data <= 8'hF0;
                    spi_start   <= 1'b1;
                    state       <= ST_WAIT_DATA1;
                end

                ST_WAIT_DATA1: begin
                    if (spi_done) begin
                        init_busy <= 1'b0;
                        init_done <= 1'b1;
                        state     <= ST_READY;
                    end
                end

                ST_READY: begin
                    init_done <= 1'b1;
                    if (frame_ready)
                        frame_src_port <= 1'b0;
                end

                default: begin
                    init_error <= 1'b1;
                    state      <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
