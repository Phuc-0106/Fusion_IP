// =============================================================
// fusion_ip_top.sv — UKF Sensor Fusion IP  Top-Level Module
//
// Implements an Unscented Kalman Filter (UKF) for multi-sensor
// fusion of GPS, IMU, and Odometer data.
//
// ┌─────────────────────────────────────────────────────────────┐
// │                    fusion_ip_top                            │
// │  ┌───────────┐  ┌──────────────────────────────────────┐   │
// │  │  Sensor   │  │         UKF Controller (FSM)         │   │
// │  │  Input    │→ │  IDLE→SIGMA_GEN→PREDICT→UPDATE→WB    │   │
// │  │  Block    │  └──┬──────┬──────────┬──────────────┬──┘   │
// │  └───────────┘     │      │          │              │       │
// │  ┌──────────────────▼──┐  │   ┌──────▼────┐  ┌─────▼────┐  │
// │  │  State Memory Reg   │  │   │  Predict  │  │  Update  │  │
// │  │  (256 × 32-bit)     │  │   │  Block    │  │  Block   │  │
// │  └──────────────────▲──┘  │   └───────────┘  └──────────┘  │
// │                      │    │                                  │
// │  ┌───────────────────┴──┐  │                                 │
// │  │  Sigma-Point Gen     │◄─┘                                 │
// │  └──────────────────────┘                                    │
// │  ┌────────────────────────────────────────────────────────┐  │
// │  │  AXI4-Lite MMIO Register Bank                          │  │
// │  └────────────────────────────────────────────────────────┘  │
// └─────────────────────────────────────────────────────────────┘
//
// AXI4-Lite MMIO Register Map (32-bit word, byte-addressed):
// All data words use IEEE-754 single-precision (FP32) encoding.
//   0x00: CTRL    [0]=start, [1]=soft_reset
//   0x04: STATUS  [0]=busy, [1]=valid, [2]=error, [3]=sensor_map
//   0x08: GPS_X   FP32 GPS x  (write to load measurement)
//   0x0C: GPS_Y   FP32 GPS y
//   0x10: IMU_PSI FP32 heading ψ
//   0x14: IMU_DOT FP32 yaw rate ψ̇
//   0x18: ODOM_V  FP32 velocity v
//   0x1C: DT      FP32 sample time dt (default 0.04s, writable; 0 → use 1.0s internally)
//   0x20: OUT_X   FP32 estimated x  (read-only)
//   0x24: OUT_Y   FP32 estimated y
//   0x28: OUT_V   FP32 estimated v
//   0x2C: OUT_PSI FP32 estimated ψ
//   0x30: OUT_DOT FP32 estimated ψ̇
//   0x34: IRQ_CLR [0]=write 1 to clear IRQ
// =============================================================
`include "params.vh"

module fusion_ip_top #(
    parameter int DATA_W   = `DATA_W,
    parameter int FP_FRAC  = `FP_FRAC,
    parameter int N        = `N_STATE,
    parameter int N_SIG    = `N_SIGMA,
    parameter int ADDR_W   = `ADDR_W
)(
    input  logic         clk,
    input  logic         rst_n,    // active-low reset

    // ---- AXI4-Lite Slave interface ----
    // Write address channel
    input  logic [31:0]  s_axi_awaddr,
    input  logic         s_axi_awvalid,
    output logic         s_axi_awready,
    // Write data channel
    input  logic [31:0]  s_axi_wdata,
    input  logic [3:0]   s_axi_wstrb,
    input  logic         s_axi_wvalid,
    output logic         s_axi_wready,
    // Write response channel
    output logic [1:0]   s_axi_bresp,
    output logic         s_axi_bvalid,
    input  logic         s_axi_bready,
    // Read address channel
    input  logic [31:0]  s_axi_araddr,
    input  logic         s_axi_arvalid,
    output logic         s_axi_arready,
    // Read data channel
    output logic [31:0]  s_axi_rdata,
    output logic [1:0]   s_axi_rresp,
    output logic         s_axi_rvalid,
    input  logic         s_axi_rready,

    // ---- External sensor ports ----
    input  logic [63:0]  gps_data,
    input  logic         gps_valid,

    input  logic [95:0]  imu_data,
    input  logic         imu_valid,

    input  logic [31:0]  odom_data,
    input  logic         odom_valid,

    // ---- Interrupt ----
    output logic         irq
);

    // Active-high internal reset
    logic rst;
    assign rst = ~rst_n;

    // ----------------------------------------------------------
    // AXI4-Lite register file
    // ----------------------------------------------------------
    localparam int REG_CTRL     = 8'h00;
    localparam int REG_STATUS   = 8'h04;
    localparam int REG_GPS_X    = 8'h08;
    localparam int REG_GPS_Y    = 8'h0C;
    localparam int REG_IMU_PSI  = 8'h10;
    localparam int REG_IMU_DOT  = 8'h14;
    localparam int REG_ODOM_V   = 8'h18;
    localparam int REG_DT       = 8'h1C;
    localparam int REG_OUT_X    = 8'h20;
    localparam int REG_OUT_Y    = 8'h24;
    localparam int REG_OUT_V    = 8'h28;
    localparam int REG_OUT_PSI  = 8'h2C;
    localparam int REG_OUT_DOT  = 8'h30;
    localparam int REG_IRQ_CLR  = 8'h34;

    logic [31:0] reg_ctrl;
    logic [31:0] reg_gps_x, reg_gps_y;
    logic [31:0] reg_imu_psi, reg_imu_dot;
    logic [31:0] reg_odom_v;
    logic [31:0] reg_dt;
    logic [31:0] dt_effective;
    logic [31:0] reg_out_x, reg_out_y, reg_out_v, reg_out_psi, reg_out_dot;

    assign dt_effective = (reg_dt == 32'h0) ? `DT_ONE : reg_dt;

    // Derived control signals
    logic ctrl_start_pulse;
    logic ctrl_soft_rst;
    logic irq_pending;
    logic irq_clear;

    // Declared before AXI readback (STATUS register uses these)
    logic [2:0] sensor_valid_map;
    logic       status_busy_w, status_valid_w, status_error_w;
    logic       status_busy, status_valid, status_error;
    assign status_busy  = status_busy_w;
    assign status_valid = status_valid_w;
    assign status_error = status_error_w;

    // ----------------------------------------------------------
    // AXI4-Lite write logic (simplified single-cycle)
    // ----------------------------------------------------------
    logic aw_active, w_active;
    logic [7:0] aw_addr_lat;

    assign s_axi_awready = 1'b1;  // always ready
    assign s_axi_wready  = 1'b1;
    assign s_axi_bresp   = 2'b00; // OKAY
    assign s_axi_arready = 1'b1;
    assign s_axi_rresp   = 2'b00;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_ctrl     <= '0;
            reg_gps_x    <= '0;  reg_gps_y   <= '0;
            reg_imu_psi  <= '0;  reg_imu_dot <= '0;
            reg_odom_v   <= '0;
            reg_dt       <= `DT_DEFAULT;
            s_axi_bvalid <= 1'b0;
            ctrl_start_pulse <= 1'b0;
            ctrl_soft_rst    <= 1'b0;
            irq_clear        <= 1'b0;
        end else begin
            ctrl_start_pulse <= 1'b0;
            ctrl_soft_rst    <= 1'b0;
            irq_clear        <= 1'b0;

            if (s_axi_awvalid && s_axi_wvalid) begin
                case (s_axi_awaddr[7:0])
                    REG_CTRL[7:0]: begin
                        reg_ctrl         <= s_axi_wdata;
                        ctrl_start_pulse <= s_axi_wdata[0];
                        ctrl_soft_rst    <= s_axi_wdata[1];
                    end
                    REG_GPS_X[7:0]:   reg_gps_x   <= s_axi_wdata;
                    REG_GPS_Y[7:0]:   reg_gps_y   <= s_axi_wdata;
                    REG_IMU_PSI[7:0]: reg_imu_psi <= s_axi_wdata;
                    REG_IMU_DOT[7:0]: reg_imu_dot <= s_axi_wdata;
                    REG_ODOM_V[7:0]:  reg_odom_v  <= s_axi_wdata;
                    REG_DT[7:0]:      reg_dt      <= s_axi_wdata;
                    REG_IRQ_CLR[7:0]: irq_clear   <= s_axi_wdata[0];
                    default: ;
                endcase
                s_axi_bvalid <= 1'b1;
            end else if (s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // AXI4-Lite read logic
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= '0;
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_rvalid <= 1'b1;
                case (s_axi_araddr[7:0])
                    REG_CTRL[7:0]:    s_axi_rdata <= reg_ctrl;
                    REG_STATUS[7:0]:  s_axi_rdata <= {28'b0,
                                                       sensor_valid_map,
                                                       status_error,
                                                       status_valid,
                                                       status_busy};
                    REG_GPS_X[7:0]:   s_axi_rdata <= reg_gps_x;
                    REG_GPS_Y[7:0]:   s_axi_rdata <= reg_gps_y;
                    REG_IMU_PSI[7:0]: s_axi_rdata <= reg_imu_psi;
                    REG_IMU_DOT[7:0]: s_axi_rdata <= reg_imu_dot;
                    REG_ODOM_V[7:0]:  s_axi_rdata <= reg_odom_v;
                    REG_DT[7:0]:      s_axi_rdata <= reg_dt;
                    REG_OUT_X[7:0]:   s_axi_rdata <= reg_out_x;
                    REG_OUT_Y[7:0]:   s_axi_rdata <= reg_out_y;
                    REG_OUT_V[7:0]:   s_axi_rdata <= reg_out_v;
                    REG_OUT_PSI[7:0]: s_axi_rdata <= reg_out_psi;
                    REG_OUT_DOT[7:0]: s_axi_rdata <= reg_out_dot;
                    default:          s_axi_rdata <= 32'hDEAD_BEEF;
                endcase
            end else if (s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // ----------------------------------------------------------
    // IRQ logic
    // ----------------------------------------------------------
    logic ctrl_irq_raw;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            irq_pending <= 1'b0;
            irq         <= 1'b0;
        end else begin
            if (ctrl_irq_raw)   irq_pending <= 1'b1;
            if (irq_clear)      irq_pending <= 1'b0;
            irq <= irq_pending;
        end
    end

    // ----------------------------------------------------------
    // Internal wires
    // ----------------------------------------------------------
    // Sensor input block
    logic [2:0]  sensor_err;
    logic        gps_rd_w, imu_rd_w, odom_rd_w;
    logic signed [DATA_W-1:0] s_gps_x, s_gps_y;
    logic signed [DATA_W-1:0] s_imu_psi, s_imu_dot, s_imu_accel;
    logic signed [DATA_W-1:0] s_odom_vel;

    // State memory
    logic                     mem_wr_en_w;
    logic [ADDR_W-1:0]        mem_wr_addr_w;
    logic [DATA_W-1:0]        mem_wr_data_w;
    logic                     mem_rd_en_a_w;
    logic [ADDR_W-1:0]        mem_rd_addr_a_w;
    logic [DATA_W-1:0]        mem_rd_data_a_w;
    logic                     mem_rd_en_b_w;
    logic [ADDR_W-1:0]        mem_rd_addr_b_w;
    logic [DATA_W-1:0]        mem_rd_data_b_w;

    // Sigma-point generator
    logic                     sg_start_w, sg_done_w, sg_err_w;
    logic                     sg_mem_wr_en_w;
    logic [ADDR_W-1:0]        sg_mem_wr_addr_w;
    logic [DATA_W-1:0]        sg_mem_wr_data_w;
    logic                     sg_mem_rd_en_w;
    logic [ADDR_W-1:0]        sg_mem_rd_addr_w;

    // Predict block
    logic                     pb_start_w, pb_done_w;
    logic                     pb_mem_wr_en_w;
    logic [ADDR_W-1:0]        pb_mem_wr_addr_w;
    logic [DATA_W-1:0]        pb_mem_wr_data_w;
    logic                     pb_mem_rd_en_w;
    logic [ADDR_W-1:0]        pb_mem_rd_addr_w;
    logic [N*DATA_W-1:0]      pb_x_pred_bus_w;

    // Update block
    logic                     ub_start_w, ub_done_w, ub_err_w;
    logic                     ub_mem_wr_en_w;
    logic [ADDR_W-1:0]        ub_mem_wr_addr_w;
    logic [DATA_W-1:0]        ub_mem_wr_data_w;
    logic                     ub_mem_rd_en_w;
    logic [ADDR_W-1:0]        ub_mem_rd_addr_w;
    logic [N*DATA_W-1:0]      ub_update_result_w;

    // Controller outputs
    logic signed [DATA_W-1:0] out_x_w [0:N-1];
    logic                     out_valid_w;
    logic [1:0]               mem_b_sel_w;
    logic [2:0]               sensor_map_lat_w;

    // Mem port-B mux: route based on which block the controller has active
    always_comb begin
        case (mem_b_sel_w)
            2'd0: begin  // sigma-point generator active
                mem_rd_en_b_w   = sg_mem_rd_en_w;
                mem_rd_addr_b_w = sg_mem_rd_addr_w;
            end
            2'd1: begin  // predict block active
                mem_rd_en_b_w   = pb_mem_rd_en_w;
                mem_rd_addr_b_w = pb_mem_rd_addr_w;
            end
            default: begin  // update block (or idle)
                mem_rd_en_b_w   = ub_mem_rd_en_w;
                mem_rd_addr_b_w = ub_mem_rd_addr_w;
            end
        endcase
    end

    // ----------------------------------------------------------
    // Capture final state to MMIO output registers
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            reg_out_x   <= '0;  reg_out_y   <= '0;
            reg_out_v   <= '0;  reg_out_psi <= '0;
            reg_out_dot <= '0;
        end else if (out_valid_w) begin
            reg_out_x   <= out_x_w[0];
            reg_out_y   <= out_x_w[1];
            reg_out_v   <= out_x_w[2];
            reg_out_psi <= out_x_w[3];
            reg_out_dot <= out_x_w[4];
        end
    end

    // ----------------------------------------------------------
    // Sub-module instantiations
    // ----------------------------------------------------------

    // ---- Sensor Input Block ----
    sensor_input_block #(.DATA_W(DATA_W)) u_sensor (
        .clk             (clk),
        .rst             (rst),
        .gps_data        (gps_data),
        .gps_valid       (gps_valid),
        .imu_data        (imu_data),
        .imu_valid       (imu_valid),
        .odom_data       (odom_data),
        .odom_valid      (odom_valid),
        .gps_rd          (gps_rd_w),
        .imu_rd          (imu_rd_w),
        .odom_rd         (odom_rd_w),
        .gps_x           (s_gps_x),
        .gps_y           (s_gps_y),
        .imu_psi         (s_imu_psi),
        .imu_psi_dot     (s_imu_dot),
        .imu_accel       (s_imu_accel),
        .odom_vel        (s_odom_vel),
        .sensor_valid_map(sensor_valid_map),
        .sensor_err      (sensor_err)
    );

    // ---- State Memory ----
    state_mem_reg #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_mem (
        .clk        (clk),
        .rst        (rst),
        .wr_en      (mem_wr_en_w),
        .wr_addr    (mem_wr_addr_w),
        .wr_data    (mem_wr_data_w),
        .rd_en_a    (mem_rd_en_a_w),
        .rd_addr_a  (mem_rd_addr_a_w),
        .rd_data_a  (mem_rd_data_a_w),
        .rd_en_b    (mem_rd_en_b_w),
        .rd_addr_b  (mem_rd_addr_b_w),
        .rd_data_b  (mem_rd_data_b_w)
    );

    // ---- Sigma-Point Generator ----
    sigma_point_generator #(.DATA_W(DATA_W), .FP_FRAC(FP_FRAC),
                             .N(N), .N_SIG(N_SIG)) u_sigma_gen (
        .clk         (clk),
        .rst         (rst),
        .start       (sg_start_w),
        .done        (sg_done_w),
        .sigma_err   (sg_err_w),
        .mem_rd_en   (sg_mem_rd_en_w),
        .mem_rd_addr (sg_mem_rd_addr_w),
        .mem_rd_data (mem_rd_data_b_w),
        .mem_wr_en   (sg_mem_wr_en_w),
        .mem_wr_addr (sg_mem_wr_addr_w),
        .mem_wr_data (sg_mem_wr_data_w),
        .gamma       (`UKF_GAMMA)
    );

    // ---- Predict Block ----
    predict_block #(.DATA_W(DATA_W), .FP_FRAC(FP_FRAC),
                    .N(N), .N_SIG(N_SIG)) u_predict (
        .clk            (clk),
        .rst            (rst),
        .start          (pb_start_w),
        .done           (pb_done_w),
        .dt             (dt_effective),
        .wm0            (`UKF_WM0),
        .wmi            (`UKF_WMI),
        .wc0            (`UKF_WC0),
        .wci            (`UKF_WCI),
        .mem_rd_en      (pb_mem_rd_en_w),
        .mem_rd_addr    (pb_mem_rd_addr_w),
        .mem_rd_data    (mem_rd_data_b_w),
        .mem_wr_en      (pb_mem_wr_en_w),
        .mem_wr_addr    (pb_mem_wr_addr_w),
        .mem_wr_data    (pb_mem_wr_data_w),
        .x_pred_bus     (pb_x_pred_bus_w),
        .pred_point_done()
    );

    // ---- Update Block ----
    update_block #(.DATA_W(DATA_W), .FP_FRAC(FP_FRAC), .N(N)) u_update (
        .clk             (clk),
        .rst             (rst),
        .start           (ub_start_w),
        .sensor_valid_map(sensor_map_lat_w),
        .done            (ub_done_w),
        .upd_err         (ub_err_w),
        .meas_gps_x      (s_gps_x),
        .meas_gps_y      (s_gps_y),
        .meas_imu_psi    (s_imu_psi),
        .meas_imu_dot    (s_imu_dot),
        .meas_odom_v     (s_odom_vel),
        .mem_rd_en       (ub_mem_rd_en_w),
        .mem_rd_addr     (ub_mem_rd_addr_w),
        .mem_rd_data     (mem_rd_data_b_w),
        .mem_wr_en       (ub_mem_wr_en_w),
        .mem_wr_addr     (ub_mem_wr_addr_w),
        .mem_wr_data     (ub_mem_wr_data_w),
        .update_result   (ub_update_result_w)
    );

    // ---- UKF Controller ----
    ukf_controller #(.DATA_W(DATA_W), .FP_FRAC(FP_FRAC),
                     .N(N), .N_SIG(N_SIG)) u_ctrl (
        .clk             (clk),
        .rst             (rst),
        .ctrl_start      (ctrl_start_pulse),
        .ctrl_soft_rst   (ctrl_soft_rst),
        .status_busy     (status_busy_w),
        .status_valid    (status_valid_w),
        .status_error    (status_error_w),
        .irq             (ctrl_irq_raw),
        .sensor_valid_map(sensor_valid_map),
        .gps_rd          (gps_rd_w),
        .imu_rd          (imu_rd_w),
        .odom_rd         (odom_rd_w),
        .meas_gps_x      (s_gps_x),
        .meas_gps_y      (s_gps_y),
        .meas_imu_psi    (s_imu_psi),
        .meas_imu_dot    (s_imu_dot),
        .meas_odom_v     (s_odom_vel),
        .mem_wr_en       (mem_wr_en_w),
        .mem_wr_addr     (mem_wr_addr_w),
        .mem_wr_data     (mem_wr_data_w),
        .mem_rd_en_a     (mem_rd_en_a_w),
        .mem_rd_addr_a   (mem_rd_addr_a_w),
        .mem_rd_data_a   (mem_rd_data_a_w),
        .sg_start        (sg_start_w),
        .sg_done         (sg_done_w),
        .sg_err          (sg_err_w),
        .sg_mem_wr_en    (sg_mem_wr_en_w),
        .sg_mem_wr_addr  (sg_mem_wr_addr_w),
        .sg_mem_wr_data  (sg_mem_wr_data_w),
        .pb_start        (pb_start_w),
        .pb_done         (pb_done_w),
        .pb_mem_wr_en    (pb_mem_wr_en_w),
        .pb_mem_wr_addr  (pb_mem_wr_addr_w),
        .pb_mem_wr_data  (pb_mem_wr_data_w),
        .pb_x_pred_bus   (pb_x_pred_bus_w),
        .ub_start        (ub_start_w),
        .ub_done         (ub_done_w),
        .ub_err          (ub_err_w),
        .ub_mem_wr_en    (ub_mem_wr_en_w),
        .ub_mem_wr_addr  (ub_mem_wr_addr_w),
        .ub_mem_wr_data  (ub_mem_wr_data_w),
        .ub_update_result(ub_update_result_w),
        .out_x           (out_x_w),
        .out_valid       (out_valid_w),
        .mem_b_sel       (mem_b_sel_w),
        .sensor_map_out  (sensor_map_lat_w)
    );

endmodule
