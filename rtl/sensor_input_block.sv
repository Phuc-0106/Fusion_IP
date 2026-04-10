// =============================================================
// sensor_input_block.sv — Multi-Sensor Input Aggregator
//
// Handles three sensor streams:
//   GPS     : gps_data[63:0]  → x_pos[31:0], y_pos[31:0]  (Q8.24 m)
//   IMU     : imu_data[95:0]  → psi[31:0], psi_dot[31:0],
//                                accel_fwd[31:0]             (Q8.24)
//   Odometer: odom_data[31:0] → velocity v                  (Q8.24 m/s)
//
// Features
//   • 2-FF synchroniser on each _valid pulse (CDC)
//   • Per-sensor FIFO (depth 4) for buffering bursts
//   • FP32: all latched frames accepted on valid pulse (signed physics OK).
//     (Legacy Q8.24 used MSB sentinel; removed for float32 sensors.)
//   • sensor_valid_map[2:0] = {gps, imu, odom} indicates
//     at least one unread sample is available
//   • Controller reads one frame per sensor by asserting
//     gps_rd / imu_rd / odom_rd for one cycle
// =============================================================
`include "params.vh"

module sensor_input_block #(
    parameter int DATA_W = `DATA_W    // 32 bits per field
)(
    input  logic         clk,
    input  logic         rst,

    // ---- GPS input (two Q8.24 fields = 64 bits) ----
    input  logic [63:0]  gps_data,    // [63:32]=x, [31:0]=y
    input  logic         gps_valid,   // pulse: new GPS frame

    // ---- IMU input (three Q8.24 fields = 96 bits) ----
    input  logic [95:0]  imu_data,    // [95:64]=ψ, [63:32]=ψ̇, [31:0]=accel_fwd
    input  logic         imu_valid,

    // ---- Odometer input (one Q8.24 field = 32 bits) ----
    input  logic [31:0]  odom_data,   // velocity v
    input  logic         odom_valid,

    // ---- Controller read ports ----
    input  logic         gps_rd,      // pop one GPS frame
    input  logic         imu_rd,
    input  logic         odom_rd,

    // ---- Decoded output fields ----
    output logic signed [DATA_W-1:0] gps_x,
    output logic signed [DATA_W-1:0] gps_y,
    output logic signed [DATA_W-1:0] imu_psi,
    output logic signed [DATA_W-1:0] imu_psi_dot,
    output logic signed [DATA_W-1:0] imu_accel,
    output logic signed [DATA_W-1:0] odom_vel,

    // ---- Status ----
    output logic [2:0]   sensor_valid_map,  // {gps_avail, imu_avail, odom_avail}
    output logic [2:0]   sensor_err         // sticky data-validation errors
);

    // ----------------------------------------------------------
    // 2-FF synchronisers for incoming valid pulses
    // ----------------------------------------------------------
    logic [1:0] gps_sync, imu_sync, odom_sync;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            gps_sync  <= 2'b00;
            imu_sync  <= 2'b00;
            odom_sync <= 2'b00;
        end else begin
            gps_sync  <= {gps_sync[0],  gps_valid};
            imu_sync  <= {imu_sync[0],  imu_valid};
            odom_sync <= {odom_sync[0], odom_valid};
        end
    end

    // Rising-edge detect after synchroniser
    logic gps_pulse, imu_pulse, odom_pulse;
    assign gps_pulse  = gps_sync[1]  & ~gps_sync[0];   // intentional: MSB was 1, now sample
    // Note: use gps_sync[1] as the stable signal after 2-FF sync
    // We write to FIFO when the synchronised valid rises
    // Simple approach: use gps_sync[1] level to write once per frame
    // (external valid is expected to be a single-cycle pulse)

    // ----------------------------------------------------------
    // GPS FIFO  (64-bit wide: x, y)
    // ----------------------------------------------------------
    logic        gps_wr_en;
    logic [63:0] gps_wr_data;
    logic [63:0] gps_rd_data;
    logic        gps_fifo_full, gps_fifo_empty;

    // FP32: signed physical quantities (e.g. WGS84 x/y, southern/western coords)
    // may have sign bit set — do not treat MSB as "invalid sentinel" (Q8.24 legacy).
    logic gps_valid_frame;
    assign gps_valid_frame = 1'b1;
    assign gps_wr_en       = gps_sync[1] & gps_valid_frame & ~gps_fifo_full;

    sync_fifo #(.DATA_W(64), .DEPTH(4)) u_gps_fifo (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (gps_wr_en),
        .wr_data (gps_data),
        .rd_en   (gps_rd & ~gps_fifo_empty),
        .rd_data (gps_rd_data),
        .full    (gps_fifo_full),
        .empty   (gps_fifo_empty),
        .count   ()
    );

    // ----------------------------------------------------------
    // IMU FIFO  (96-bit wide: ψ, ψ̇, accel)
    // ----------------------------------------------------------
    logic        imu_wr_en;
    logic [95:0] imu_rd_data;
    logic        imu_fifo_full, imu_fifo_empty;

    logic imu_valid_frame;
    assign imu_valid_frame = 1'b1;
    assign imu_wr_en       = imu_sync[1] & imu_valid_frame & ~imu_fifo_full;

    sync_fifo #(.DATA_W(96), .DEPTH(4)) u_imu_fifo (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (imu_wr_en),
        .wr_data (imu_data),
        .rd_en   (imu_rd & ~imu_fifo_empty),
        .rd_data (imu_rd_data),
        .full    (imu_fifo_full),
        .empty   (imu_fifo_empty),
        .count   ()
    );

    // ----------------------------------------------------------
    // Odometer FIFO  (32-bit)
    // ----------------------------------------------------------
    logic        odom_wr_en;
    logic [31:0] odom_rd_data;
    logic        odom_fifo_full, odom_fifo_empty;

    logic odom_valid_frame;
    assign odom_valid_frame = 1'b1;
    assign odom_wr_en       = odom_sync[1] & odom_valid_frame & ~odom_fifo_full;

    sync_fifo #(.DATA_W(32), .DEPTH(4)) u_odom_fifo (
        .clk     (clk),
        .rst     (rst),
        .wr_en   (odom_wr_en),
        .wr_data (odom_data),
        .rd_en   (odom_rd & ~odom_fifo_empty),
        .rd_data (odom_rd_data),
        .full    (odom_fifo_full),
        .empty   (odom_fifo_empty),
        .count   ()
    );

    // sync_fifo registers rd_data one cycle after rd_en (not fall-through). Capturing
    // on the same posedge as gps_rd uses stale rd_data (often 0 on first pop), which
    // breaks UKF cycle 1 (innovation pulls state toward wrong measurement).
    logic gps_rd_req_d, imu_rd_req_d, odom_rd_req_d;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            gps_rd_req_d  <= 1'b0;
            imu_rd_req_d  <= 1'b0;
            odom_rd_req_d <= 1'b0;
        end else begin
            gps_rd_req_d  <= gps_rd && !gps_fifo_empty;
            imu_rd_req_d  <= imu_rd && !imu_fifo_empty;
            odom_rd_req_d <= odom_rd && !odom_fifo_empty;
        end
    end

    // ----------------------------------------------------------
    // Latched output registers — hold last popped frame
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            gps_x       <= '0;
            gps_y       <= '0;
            imu_psi     <= '0;
            imu_psi_dot <= '0;
            imu_accel   <= '0;
            odom_vel    <= '0;
        end else begin
            if (gps_rd_req_d) begin
                gps_x <= $signed(gps_rd_data[63:32]);
                gps_y <= $signed(gps_rd_data[31: 0]);
            end
            if (imu_rd_req_d) begin
                imu_psi     <= $signed(imu_rd_data[95:64]);
                imu_psi_dot <= $signed(imu_rd_data[63:32]);
                imu_accel   <= $signed(imu_rd_data[31: 0]);
            end
            if (odom_rd_req_d) begin
                odom_vel <= $signed(odom_rd_data[31:0]);
            end
        end
    end

    // ----------------------------------------------------------
    // Status and error flags
    // ----------------------------------------------------------
    assign sensor_valid_map = {~gps_fifo_empty, ~imu_fifo_empty, ~odom_fifo_empty};

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            sensor_err <= 3'b000;
        end else begin
            // Set error bit when a frame is dropped due to overflow
            if (gps_sync[1]  && gps_fifo_full)  sensor_err[2] <= 1'b1;
            if (imu_sync[1]  && imu_fifo_full)   sensor_err[1] <= 1'b1;
            if (odom_sync[1] && odom_fifo_full)  sensor_err[0] <= 1'b1;
        end
    end

endmodule
