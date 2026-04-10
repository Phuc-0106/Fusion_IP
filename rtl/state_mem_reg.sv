// =============================================================
// state_mem_reg.sv — UKF Centralised State Memory
//
// 256 × 32-bit synchronous single-port SRAM with one write port
// and two independent read ports.
//
// Memory map (see params.vh for full details):
//   0x00-0x04  : state vector x[5]
//   0x05-0x1D  : covariance P[5×5]
//   0x1E-0x36  : process noise Q[5×5]
//   0x37-0x3A  : GPS meas. noise R_gps[2×2]
//   0x3B-0x3E  : IMU meas. noise R_imu[2×2]
//   0x3F       : Odom meas. noise R_odom
//   0x40-0x76  : sigma points [11×5]
//   0x77-0xAD  : predicted sigma points [11×5]
//   0xAE-0xB2  : predicted mean x_pred[5]
//   0xB3-0xCB  : predicted covariance P_pred[5×5]
//   0xCC-0xE4  : LDL factor L[5×5] row-major (sigma_point_generator, ADDR_L_UKF)
//   0xE5-0xE9  : LDL diagonal D[5] (ADDR_D_UKF)
//   0xEA-0xFF  : scratch (22 words)
//
// Write port  : controlled exclusively by the UKF controller
// Read port A : controller / general
// Read port B : computation blocks (sigma gen / predict / update)
//               — address registered, data available next cycle
// =============================================================
`include "params.vh"

module state_mem_reg #(
    parameter int DATA_W  = `DATA_W,   // 32
    parameter int ADDR_W  = `ADDR_W,   // 8  → 256 words
    parameter int MEM_SZ  = 256
)(
    input  logic                 clk,
    input  logic                 rst,

    // ---- Write port (controller only) ----
    input  logic                 wr_en,
    input  logic [ADDR_W-1:0]    wr_addr,
    input  logic [DATA_W-1:0]    wr_data,

    // ---- Read port A (controller / status) ----
    input  logic                 rd_en_a,
    input  logic [ADDR_W-1:0]    rd_addr_a,
    output logic [DATA_W-1:0]    rd_data_a,

    // ---- Read port B (computation blocks) ----
    input  logic                 rd_en_b,
    input  logic [ADDR_W-1:0]    rd_addr_b,
    output logic [DATA_W-1:0]    rd_data_b
);

    logic [DATA_W-1:0] mem [0:MEM_SZ-1];

    // Synchronous write
    always_ff @(posedge clk) begin
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

    // Synchronous read — port A
    always_ff @(posedge clk or posedge rst) begin
        if (rst)
            rd_data_a <= '0;
        else if (rd_en_a)
            rd_data_a <= mem[rd_addr_a];
    end

    // Combinational read — port B
    // Computation blocks (sigma_gen, predict, update) drive the address
    // through a combinational mux; a registered read would add an extra
    // pipeline stage that the load loops do not account for.
    assign rd_data_b = mem[rd_addr_b];

endmodule
