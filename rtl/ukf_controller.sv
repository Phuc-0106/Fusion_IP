// =============================================================
// ukf_controller.sv — UKF Main Sequencer / FSM
//
// Controls the full UKF pipeline:
//
//  ┌──────────────────────────────────────────────────────────┐
//  │  IDLE → SIGMA_GEN → PREDICT → PRED_MEAN →               │
//  │         UPDATE_GPS → UPDATE_IMU → UPDATE_ODOM →          │
//  │         WRITEBACK → IDLE                                  │
//  └──────────────────────────────────────────────────────────┘
//
// Responsibilities:
//   • Arm each computation block (start pulse + done wait)
//   • Arbitrate state-memory write access between computation
//     blocks and the controller itself
//   • Initialise state memory from MMIO register bank
//     (prior to the first UKF cycle)
//   • Writeback final x̂, P to MMIO output registers
//   • Drive status/IRQ to host
//   • Handle sensor unavailability (skip update passes)
//
// Write-port arbitration (priority):
//   controller > sigma_gen > predict > update
//   (only one block active per FSM state, so no true conflict)
// =============================================================
`include "params.vh"

module ukf_controller #(
    parameter int DATA_W   = `DATA_W,
    parameter int FP_FRAC  = `FP_FRAC,
    parameter int N        = `N_STATE,
    parameter int N_SIG    = `N_SIGMA
)(
    input  logic                     clk,
    input  logic                     rst,

    // ---- Host control / status ----
    input  logic                     ctrl_start,     // one-cycle start pulse
    input  logic                     ctrl_soft_rst,
    output logic                     status_busy,
    output logic                     status_valid,
    output logic                     status_error,
    output logic                     irq,            // high one cycle when done

    // ---- Sensor valid map from sensor_input_block ----
    input  logic [2:0]               sensor_valid_map,
    // ---- Sensor read strobes (pop one frame each) ----
    output logic                     gps_rd,
    output logic                     imu_rd,
    output logic                     odom_rd,

    // ---- Decoded sensor measurements ----
    input  logic signed [DATA_W-1:0] meas_gps_x,
    input  logic signed [DATA_W-1:0] meas_gps_y,
    input  logic signed [DATA_W-1:0] meas_imu_psi,
    input  logic signed [DATA_W-1:0] meas_imu_dot,
    input  logic signed [DATA_W-1:0] meas_odom_v,

    // ---- State memory — write port (controller owns it) ----
    output logic                     mem_wr_en,
    output logic [`ADDR_W-1:0]       mem_wr_addr,
    output logic [DATA_W-1:0]        mem_wr_data,

    // ---- State memory — read port A (controller) ----
    output logic                     mem_rd_en_a,
    output logic [`ADDR_W-1:0]       mem_rd_addr_a,
    input  logic [DATA_W-1:0]        mem_rd_data_a,

    // ---- Sigma-point generator interface ----
    output logic                     sg_start,
    input  logic                     sg_done,
    input  logic                     sg_err,
    // sg uses mem read-port-B and write-port (muxed below)
    input  logic                     sg_mem_wr_en,
    input  logic [`ADDR_W-1:0]       sg_mem_wr_addr,
    input  logic [DATA_W-1:0]        sg_mem_wr_data,

    // ---- Predict block interface ----
    output logic                     pb_start,
    input  logic                     pb_done,
    // pb uses mem read-port-B and write-port (muxed below)
    input  logic                     pb_mem_wr_en,
    input  logic [`ADDR_W-1:0]       pb_mem_wr_addr,
    input  logic [DATA_W-1:0]        pb_mem_wr_data,
    input  logic [N*DATA_W-1:0]      pb_x_pred_bus,

    // ---- Update block interface ----
    output logic                     ub_start,
    input  logic                     ub_done,
    input  logic                     ub_err,
    input  logic                     ub_mem_wr_en,
    input  logic [`ADDR_W-1:0]       ub_mem_wr_addr,
    input  logic [DATA_W-1:0]        ub_mem_wr_data,
    input  logic [N*DATA_W-1:0]      ub_update_result,

    // ---- Output state vector (to MMIO) ----
    output logic signed [DATA_W-1:0] out_x  [0:N-1],
    output logic                     out_valid,

    // ---- Port-B memory-mux select ----
    output logic [1:0]               mem_b_sel,  // 0=sigma_gen, 1=predict, 2=update

    // ---- Latched sensor map (captured before FIFO pop) ----
    output logic [2:0]               sensor_map_out
);

    // ----------------------------------------------------------
    // UKF parameters passed to submodules
    // ----------------------------------------------------------
    localparam signed [DATA_W-1:0] GAMMA = `UKF_GAMMA;
    localparam signed [DATA_W-1:0] WM0   = `UKF_WM0;
    localparam signed [DATA_W-1:0] WMI   = `UKF_WMI;
    localparam signed [DATA_W-1:0] WC0   = `UKF_WC0;
    localparam signed [DATA_W-1:0] WCI   = `UKF_WCI;
    localparam signed [DATA_W-1:0] DT    = `DT_DEFAULT;

    // ----------------------------------------------------------
    // FSM state encoding
    // ┌──────────────────────────────────────────────────────┐
    // │  IDLE                                                │
    // │    │ ctrl_start & sensor_valid_map ≠ 0               │
    // │    ▼                                                 │
    // │  READ_SENSORS  (pop one frame per sensor)            │
    // │    ▼                                                 │
    // │  SIGMA_GEN  ──done──►  PREDICT                       │
    // │                            │done                     │
    // │                       PRED_MEAN (internal to predict)│
    // │                            │                         │
    // │                       UPDATE_GPS ──done──►           │
    // │                       UPDATE_IMU ──done──►           │
    // │                       UPDATE_ODOM──done──►           │
    // │                       WRITEBACK                      │
    // │                            │                         │
    // │                         IDLE                         │
    // └──────────────────────────────────────────────────────┘
    // ----------------------------------------------------------
    typedef enum logic [3:0] {
        C_IDLE,
        C_READ_SENSORS,
        C_SIGMA_GEN,
        C_WAIT_SIGMA,
        C_PREDICT,
        C_WAIT_PREDICT,
        C_UPDATE,
        C_WAIT_UPDATE,
        C_WRITEBACK,
        C_ERROR
    } ctrl_state_t;

    ctrl_state_t ctrl_state;

    // Latched sensor availability — captured before FIFOs are popped
    logic [2:0] sensor_map_lat;

    // ----------------------------------------------------------
    // Port-B read-mux select — active for the full duration of each block
    // ----------------------------------------------------------
    assign sensor_map_out = sensor_map_lat;

    always_comb begin
        case (ctrl_state)
            C_SIGMA_GEN, C_WAIT_SIGMA: mem_b_sel = 2'd0;
            C_PREDICT,   C_WAIT_PREDICT: mem_b_sel = 2'd1;
            default:                     mem_b_sel = 2'd2;
        endcase
    end

    // ----------------------------------------------------------
    // Write-port multiplexer
    // ----------------------------------------------------------
    // Priority: ctrl > sg > pb > ub (only one active per state)
    always_comb begin
        // Default: controller drives write port
        mem_wr_en   = 1'b0;
        mem_wr_addr = '0;
        mem_wr_data = '0;

        case (ctrl_state)
            C_SIGMA_GEN, C_WAIT_SIGMA: begin
                mem_wr_en   = sg_mem_wr_en;
                mem_wr_addr = sg_mem_wr_addr;
                mem_wr_data = sg_mem_wr_data;
            end
            C_PREDICT, C_WAIT_PREDICT: begin
                mem_wr_en   = pb_mem_wr_en;
                mem_wr_addr = pb_mem_wr_addr;
                mem_wr_data = pb_mem_wr_data;
            end
            C_UPDATE, C_WAIT_UPDATE: begin
                mem_wr_en   = ub_mem_wr_en;
                mem_wr_addr = ub_mem_wr_addr;
                mem_wr_data = ub_mem_wr_data;
            end
            default: begin
                mem_wr_en   = 1'b0;
                mem_wr_addr = '0;
                mem_wr_data = '0;
            end
        endcase
    end

    // ----------------------------------------------------------
    // FSM sequential logic
    // ----------------------------------------------------------
    always_ff @(posedge clk or posedge rst) begin
        if (rst || ctrl_soft_rst) begin
            ctrl_state   <= C_IDLE;
            status_busy  <= 1'b0;
            status_valid <= 1'b0;
            status_error <= 1'b0;
            irq          <= 1'b0;
            sg_start     <= 1'b0;
            pb_start     <= 1'b0;
            ub_start     <= 1'b0;
            gps_rd       <= 1'b0;
            imu_rd       <= 1'b0;
            odom_rd      <= 1'b0;
            mem_rd_en_a  <= 1'b0;
            mem_rd_addr_a<= '0;
            out_valid    <= 1'b0;
            sensor_map_lat <= '0;
            for (int ii=0; ii<N; ii++) out_x[ii] <= '0;
        end else begin
            // Default de-assertions
            sg_start  <= 1'b0;
            pb_start  <= 1'b0;
            ub_start  <= 1'b0;
            gps_rd    <= 1'b0;
            imu_rd    <= 1'b0;
            odom_rd   <= 1'b0;
            irq       <= 1'b0;
            out_valid <= 1'b0;

            case (ctrl_state)
            // -----------------------------------------------
            C_IDLE: begin
                status_busy  <= 1'b0;
                status_error <= 1'b0;

                if (ctrl_start) begin
                    status_busy    <= 1'b1;
                    status_valid   <= 1'b0;
                    sensor_map_lat <= sensor_valid_map;
                    ctrl_state     <= C_READ_SENSORS;
                end
            end

            // -----------------------------------------------
            // Pop one frame from each available sensor FIFO
            // -----------------------------------------------
            C_READ_SENSORS: begin
                gps_rd   <= sensor_valid_map[2];
                imu_rd   <= sensor_valid_map[1];
                odom_rd  <= sensor_valid_map[0];
                ctrl_state <= C_SIGMA_GEN;
            end

            // -----------------------------------------------
            // Launch sigma-point generator
            // -----------------------------------------------
            C_SIGMA_GEN: begin
                sg_start   <= 1'b1;
                ctrl_state <= C_WAIT_SIGMA;
            end

            C_WAIT_SIGMA: begin
                if (sg_err) begin
                    status_error <= 1'b1;
                    ctrl_state   <= C_ERROR;
                end else if (sg_done) begin
                    ctrl_state <= C_PREDICT;
                end
            end

            // -----------------------------------------------
            // Launch predict block
            // -----------------------------------------------
            C_PREDICT: begin
                pb_start   <= 1'b1;
                ctrl_state <= C_WAIT_PREDICT;
            end

            C_WAIT_PREDICT: begin
                if (pb_done)
                    ctrl_state <= C_UPDATE;
            end

            // -----------------------------------------------
            // Launch update block
            // -----------------------------------------------
            C_UPDATE: begin
                ub_start   <= 1'b1;
                ctrl_state <= C_WAIT_UPDATE;
            end

            C_WAIT_UPDATE: begin
                if (ub_err) begin
                    status_error <= 1'b1;
                    ctrl_state   <= C_ERROR;
                end else if (ub_done) begin
                    ctrl_state <= C_WRITEBACK;
                end
            end

            // -----------------------------------------------
            // Writeback: capture final state from update_result bus
            // -----------------------------------------------
            C_WRITEBACK: begin
                for (int ii = 0; ii < N; ii++) begin
                    out_x[ii] <= $signed(ub_update_result[ii*DATA_W +: DATA_W]);
                end
                status_busy  <= 1'b0;
                status_valid <= 1'b1;
                out_valid    <= 1'b1;
                irq          <= 1'b1;
                ctrl_state   <= C_IDLE;
            end

            // -----------------------------------------------
            C_ERROR: begin
                status_busy  <= 1'b0;
                status_error <= 1'b1;
                irq          <= 1'b1;
                ctrl_state   <= C_IDLE;
            end
            endcase
        end
    end

endmodule
