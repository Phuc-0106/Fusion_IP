// =============================================================
// sync_fifo.sv — Synchronous FIFO
//
// Parameterised single-clock FIFO with fall-through read.
// Used to buffer asynchronously arriving sensor frames.
//
// Parameters
//   DATA_W  — data word width
//   DEPTH   — number of entries (must be power of 2)
// =============================================================

module sync_fifo #(
    parameter int DATA_W = 32,
    parameter int DEPTH  = 8    // must be 2^N
)(
    input  logic                  clk,
    input  logic                  rst,

    // Write port
    input  logic                  wr_en,
    input  logic [DATA_W-1:0]     wr_data,

    // Read port
    input  logic                  rd_en,
    output logic [DATA_W-1:0]     rd_data,

    // Status
    output logic                  full,
    output logic                  empty,
    output logic [$clog2(DEPTH):0] count
);
    localparam PTR_W = $clog2(DEPTH);

    logic [DATA_W-1:0] mem [0:DEPTH-1];
    logic [PTR_W:0]    wr_ptr;
    logic [PTR_W:0]    rd_ptr;

    assign count = wr_ptr - rd_ptr;
    assign full  = (count == DEPTH[PTR_W:0]);
    assign empty = (count == '0);

    // Write side
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= '0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[PTR_W-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read side
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_ptr  <= '0;
            rd_data <= '0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[PTR_W-1:0]];
            rd_ptr  <= rd_ptr + 1;
        end
    end

endmodule
