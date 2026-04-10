// =============================================================
// tb_fusion_ip.sv — Simulation Testbench for fusion_ip_top
//
// Test scenario:
//   1. Reset the DUT.
//   2. Wait one cycle; inject GPS, IMU, and Odometer measurements.
//   3. Write measurements via AXI4-Lite MMIO.
//   4. Assert ctrl_start (CTRL register write).
//   5. Poll STATUS register until valid = 1.
//   6. Read output state vector (OUT_X … OUT_DOT).
//   7. Repeat for a second UKF cycle with slightly different data.
//
// Measurements (all Q8.24):
//   GPS  : x=10.0 m, y=5.0 m
//   IMU  : ψ=0.3927 rad (≈22.5°), ψ̇=0.1 rad/s
//   Odom : v=2.0 m/s
//
// Expected output (approximate, depends on filter convergence):
//   The first cycle primarily uses the prior; subsequent cycles
//   converge toward the GPS/IMU/Odom measurements.
// =============================================================
`include "params.vh"
`timescale 1ns/1ps

module tb_fusion_ip;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
`ifndef FUSION_DIRECT_TB
    import fusion_tests_pkg::*;
`endif

    // ----------------------------------------------------------
    // Parameters & clock
    // ----------------------------------------------------------
    parameter int CLK_PERIOD = 10; // 100 MHz

    logic clk, rst_n;
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

`ifndef FUSION_DIRECT_TB
    fusion_axi_vif    axi_vif    (.clk(clk), .rst_n(rst_n));
    fusion_sensor_vif sensor_vif (.clk(clk), .rst_n(rst_n));
`endif

    // ----------------------------------------------------------
    // DUT-facing nets (procedural drive when +define+FUSION_DIRECT_TB)
    // ----------------------------------------------------------
`ifdef FUSION_DIRECT_TB
    logic [31:0] s_axi_awaddr;
    logic        s_axi_awvalid;
    logic        s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic  [3:0] s_axi_wstrb;
    logic        s_axi_wvalid;
    logic        s_axi_wready;
    logic  [1:0] s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;
    logic [31:0] s_axi_araddr;
    logic        s_axi_arvalid;
    logic        s_axi_arready;
    logic [31:0] s_axi_rdata;
    logic  [1:0] s_axi_rresp;
    logic        s_axi_rvalid;
    logic        s_axi_rready;

    logic [63:0] gps_data;
    logic        gps_valid;
    logic [95:0] imu_data;
    logic        imu_valid;
    logic [31:0] odom_data;
    logic        odom_valid;

    logic        irq;
`else
    wire [31:0] s_axi_awaddr;
    wire        s_axi_awvalid;
    wire        s_axi_awready;
    wire [31:0] s_axi_wdata;
    wire  [3:0] s_axi_wstrb;
    wire        s_axi_wvalid;
    wire        s_axi_wready;
    wire  [1:0] s_axi_bresp;
    wire        s_axi_bvalid;
    wire        s_axi_bready;
    wire [31:0] s_axi_araddr;
    wire        s_axi_arvalid;
    wire        s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire  [1:0] s_axi_rresp;
    wire        s_axi_rvalid;
    wire        s_axi_rready;

    wire [63:0] gps_data;
    wire        gps_valid;
    wire [95:0] imu_data;
    wire        imu_valid;
    wire [31:0] odom_data;
    wire        odom_valid;

    wire        irq;

    assign s_axi_awaddr  = axi_vif.awaddr;
    assign s_axi_awvalid = axi_vif.awvalid;
    assign s_axi_wdata   = axi_vif.wdata;
    assign s_axi_wstrb   = axi_vif.wstrb;
    assign s_axi_wvalid  = axi_vif.wvalid;
    assign s_axi_bready  = axi_vif.bready;
    assign s_axi_araddr  = axi_vif.araddr;
    assign s_axi_arvalid = axi_vif.arvalid;
    assign s_axi_rready  = axi_vif.rready;

    assign axi_vif.awready = s_axi_awready;
    assign axi_vif.wready  = s_axi_wready;
    assign axi_vif.bvalid  = s_axi_bvalid;
    assign axi_vif.bresp   = s_axi_bresp;
    assign axi_vif.arready = s_axi_arready;
    assign axi_vif.rvalid  = s_axi_rvalid;
    assign axi_vif.rdata   = s_axi_rdata;
    assign axi_vif.rresp   = s_axi_rresp;
    assign axi_vif.irq     = irq;

    assign gps_data  = sensor_vif.gps_data;
    assign gps_valid = sensor_vif.gps_valid;
    assign imu_data  = sensor_vif.imu_data;
    assign imu_valid = sensor_vif.imu_valid;
    assign odom_data = sensor_vif.odom_data;
    assign odom_valid = sensor_vif.odom_valid;
`endif

    // ----------------------------------------------------------
    // DUT instantiation
    // ----------------------------------------------------------
    fusion_ip_top dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .s_axi_awaddr   (s_axi_awaddr),
        .s_axi_awvalid  (s_axi_awvalid),
        .s_axi_awready  (s_axi_awready),
        .s_axi_wdata    (s_axi_wdata),
        .s_axi_wstrb    (s_axi_wstrb),
        .s_axi_wvalid   (s_axi_wvalid),
        .s_axi_wready   (s_axi_wready),
        .s_axi_bresp    (s_axi_bresp),
        .s_axi_bvalid   (s_axi_bvalid),
        .s_axi_bready   (s_axi_bready),
        .s_axi_araddr   (s_axi_araddr),
        .s_axi_arvalid  (s_axi_arvalid),
        .s_axi_arready  (s_axi_arready),
        .s_axi_rdata    (s_axi_rdata),
        .s_axi_rresp    (s_axi_rresp),
        .s_axi_rvalid   (s_axi_rvalid),
        .s_axi_rready   (s_axi_rready),
        .gps_data       (gps_data),
        .gps_valid      (gps_valid),
        .imu_data       (imu_data),
        .imu_valid      (imu_valid),
        .odom_data      (odom_data),
        .odom_valid     (odom_valid),
        .irq            (irq)
    );

`ifdef FUSION_DIRECT_TB
    // ----------------------------------------------------------
    // FP32 encoding helper
    // ----------------------------------------------------------
    function automatic logic [31:0] to_q824;
        input real val;
        begin
            to_q824 = $shortrealtobits(shortreal'(val));
        end
    endfunction

    // ----------------------------------------------------------
    // AXI4-Lite write task
    // ----------------------------------------------------------
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);
            s_axi_awaddr  = addr;
            s_axi_awvalid = 1'b1;
            s_axi_wdata   = data;
            s_axi_wstrb   = 4'hF;
            s_axi_wvalid  = 1'b1;
            s_axi_bready  = 1'b1;
            @(posedge clk);
            s_axi_awvalid = 1'b0;
            s_axi_wvalid  = 1'b0;
        end
    endtask

    // AXI4-Lite read task
    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);
            s_axi_araddr  = addr;
            s_axi_arvalid = 1'b1;
            s_axi_rready  = 1'b1;
            @(posedge clk);
            s_axi_arvalid = 1'b0;
            wait(s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
        end
    endtask

    // ----------------------------------------------------------
    // Sensor injection task
    // ----------------------------------------------------------
    task inject_sensors;
        input real gx, gy;     // GPS x, y  [m]
        input real psi, pdot;  // IMU ψ [rad], ψ̇ [rad/s]
        input real vel;        // Odometer v [m/s]
        begin
            // Drive sensor ports
            gps_data  = {to_q824(gx), to_q824(gy)};
            imu_data  = {to_q824(psi), to_q824(pdot), 32'h0};
            odom_data = to_q824(vel);

            @(posedge clk);
            gps_valid  = 1'b1;
            imu_valid  = 1'b1;
            odom_valid = 1'b1;
            @(posedge clk);
            gps_valid  = 1'b0;
            imu_valid  = 1'b0;
            odom_valid = 1'b0;

            // Also write to MMIO registers for direct path
            axi_write(32'h08, to_q824(gx));
            axi_write(32'h0C, to_q824(gy));
            axi_write(32'h10, to_q824(psi));
            axi_write(32'h14, to_q824(pdot));
            axi_write(32'h18, to_q824(vel));
        end
    endtask

    // ----------------------------------------------------------
    // 32-bit DUT word → real conversion helper (for display)
    // ----------------------------------------------------------
    function automatic real q2r;
        input logic [31:0] v;
        begin
            q2r = real'($bitstoshortreal(v));
        end
    endfunction

    // ----------------------------------------------------------
    // Print state helper
    // ----------------------------------------------------------
    task print_state;
        input integer cycle_num;
        logic [31:0] rx, ry, rv, rpsi, rdot;
        begin
            axi_read(32'h20, rx);
            axi_read(32'h24, ry);
            axi_read(32'h28, rv);
            axi_read(32'h2C, rpsi);
            axi_read(32'h30, rdot);

            $display("--- UKF Cycle %0d Output ---", cycle_num);
            $display("  x     = %0.6f m",    q2r(rx));
            $display("  y     = %0.6f m",    q2r(ry));
            $display("  v     = %0.6f m/s",  q2r(rv));
            $display("  psi   = %0.6f rad",  q2r(rpsi));
            $display("  psidot= %0.6f r/s",  q2r(rdot));
        end
    endtask

    // ----------------------------------------------------------
    // Dump state memory region (via hierarchical access)
    // ----------------------------------------------------------
    task dump_mem_region;
        input string label;
        input integer base;
        input integer count;
        integer k;
        begin
            $display("  [MEM] %s (addr %0d..%0d):", label, base, base+count-1);
            for (k = 0; k < count; k++)
                $display("    [%3d] = 0x%08h  (%0.6f)", base+k,
                         dut.u_mem.mem[base+k], q2r(dut.u_mem.mem[base+k]));
        end
    endtask

    // ----------------------------------------------------------
    // Dump 5×5 matrix from state memory
    // ----------------------------------------------------------
    task dump_matrix;
        input string label;
        input integer base;
        integer r, c;
        begin
            $display("  [MAT] %s :", label);
            for (r = 0; r < 5; r++)
                $display("    [%0.4f  %0.4f  %0.4f  %0.4f  %0.4f]",
                    q2r(dut.u_mem.mem[base + r*5 + 0]),
                    q2r(dut.u_mem.mem[base + r*5 + 1]),
                    q2r(dut.u_mem.mem[base + r*5 + 2]),
                    q2r(dut.u_mem.mem[base + r*5 + 3]),
                    q2r(dut.u_mem.mem[base + r*5 + 4]));
        end
    endtask

    // ----------------------------------------------------------
    // Wait for UKF cycle completion (with debug)
    // ----------------------------------------------------------
    task wait_done;
        input integer timeout_cycles;
        integer cnt;
        logic [31:0] status;
        begin
            cnt = 0;
            status = 0;
            while (!status[1] && cnt < timeout_cycles) begin
                axi_read(32'h04, status);
                cnt++;
                if (status[2]) begin
                    $display("ERROR: UKF reported error flag at poll %0d  (time=%0t)", cnt, $time);
                    $display("  ctrl_state  = %0d", dut.u_ctrl.ctrl_state);
                    $display("  sg_state    = %0d  sigma_err=%0b  sg_done=%0b",
                             dut.u_sigma_gen.sg_state,
                             dut.u_sigma_gen.sigma_err,
                             dut.u_sigma_gen.done);
                    $display("  pb_state    = %0d  pb_done=%0b",
                             dut.u_predict.pb_state,
                             dut.u_predict.done);
                    $display("  ub_state    = %0d  ub_done=%0b  upd_err=%0b",
                             dut.u_update.ub_state,
                             dut.u_update.done,
                             dut.u_update.upd_err);
                    $display("  sensor_valid_map = %03b", dut.u_sensor.sensor_valid_map);
                    dump_mem_region("x state", `ADDR_X, 5);
                    dump_matrix("P covariance", `ADDR_P);
                    dump_matrix("Q process noise", `ADDR_Q);
                    $finish;
                end
            end
            if (cnt >= timeout_cycles) begin
                $display("TIMEOUT waiting for UKF done at timeout=%0d  (time=%0t)", timeout_cycles, $time);
                $display("  ctrl_state = %0d", dut.u_ctrl.ctrl_state);
                $display("  sg_state   = %0d  sigma_err=%0b", dut.u_sigma_gen.sg_state, dut.u_sigma_gen.sigma_err);
                $display("  pb_state   = %0d", dut.u_predict.pb_state);
                $display("  ub_state   = %0d", dut.u_update.ub_state);
                $finish;
            end
            $display("UKF cycle done after ~%0d poll iterations  (time=%0t)", cnt, $time);
        end
    endtask

    // ----------------------------------------------------------
    // Main stimulus (legacy direct testbench only)
    // ----------------------------------------------------------
    integer cycle;
    integer mi;

    // Note: State RAM memory is initialized via $readmemh from state_mem_init.memh
    // This loads P (covariance), Q (process noise), R matrices (measurement noise)
    // as IEEE-754 float32 words (params.vh map). Do NOT attempt direct memory writes from TB
    // as the mem array is driven by always_ff block in RTL.

    initial begin
        // Load state memory initialization file (P, Q, R matrices)
        $readmemh("../tb/state_mem_init.memh", dut.u_mem.mem);
        $display("[INIT] State memory initialized from state_mem_init.memh");
        
        // Initialise all MMIO/sensor inputs
        rst_n         = 1'b0;
        s_axi_awvalid = 1'b0;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b1;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b1;
        gps_valid     = 1'b0;
        imu_valid     = 1'b0;
        odom_valid    = 1'b0;
        gps_data      = '0;
        imu_data      = '0;
        odom_data     = '0;

        // Reset for 10 cycles
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        $display("=== UKF Sensor Fusion IP Testbench ===");
        $display("Float32 state/mem, N=5, 2N+1=11 sigma points");
        $display("Sensor: GPS(x,y), IMU(ψ,ψ̇), Odom(v)");


        // ------ Cycle 1 ------
        $display("\n[Cycle 1] GPS=(10.0, 5.0)m  IMU=(0.393rad, 0.1r/s)  v=2.0m/s");
        inject_sensors(10.0, 5.0, 0.3927, 0.1, 2.0);
        axi_write(32'h00, 32'h1);   // START
        wait_done(50000);
        print_state(1);
        axi_write(32'h34, 32'h1);   // clear IRQ

        // ------ Cycle 2 ------
        $display("\n[Cycle 2] GPS=(10.08, 5.0)m  IMU=(0.397rad, 0.1r/s)  v=2.0m/s");
        inject_sensors(10.08, 5.0, 0.397, 0.1, 2.0);
        axi_write(32'h00, 32'h1);
        wait_done(50000);
        print_state(2);
        axi_write(32'h34, 32'h1);

        // ------ Cycle 3 (IMU only, no GPS) ------
        $display("\n[Cycle 3] GPS=NONE  IMU=(0.401rad, 0.1r/s)  v=2.0m/s");
        // Don't inject GPS this time
        imu_data  = {to_q824(0.401), to_q824(0.1), 32'h0};
        odom_data = to_q824(2.0);
        @(posedge clk);
        imu_valid  = 1'b1;
        odom_valid = 1'b1;
        @(posedge clk);
        imu_valid  = 1'b0;
        odom_valid = 1'b0;
        axi_write(32'h10, to_q824(0.401));
        axi_write(32'h14, to_q824(0.1));
        axi_write(32'h18, to_q824(2.0));
        axi_write(32'h00, 32'h1);
        wait_done(50000);
        print_state(3);
        axi_write(32'h34, 32'h1);

        // ------ Soft-reset test ------
        $display("\n[Test] Soft reset while busy");
        inject_sensors(11.0, 5.5, 0.41, 0.1, 2.0);
        axi_write(32'h00, 32'h1);   // start
        repeat (5) @(posedge clk);
        axi_write(32'h00, 32'h2);   // soft_reset
        repeat (10) @(posedge clk);
        begin
            logic [31:0] s;
            axi_read(32'h04, s);
            if (!s[0]) $display("  PASS: not busy after soft reset");
            else       $display("  FAIL: still busy after soft reset");
        end

        $display("\n=== Testbench complete ===");
        $finish;
    end

    initial begin
        $dumpfile("tb_fusion_ip.vcd");
        $dumpvars(0, tb_fusion_ip);
    end

    // ----------------------------------------------------------
    // Pipeline stage monitors (trigger on FSM transitions)
    // ----------------------------------------------------------

    // --- Controller state changes ---
    always @(dut.u_ctrl.ctrl_state) begin
        $display("[%0t] CTRL: state -> %0s (%0d)  busy=%0b valid=%0b err=%0b",
                 $time,
                 dut.u_ctrl.ctrl_state.name(),
                 dut.u_ctrl.ctrl_state,
                 dut.u_ctrl.status_busy,
                 dut.u_ctrl.status_valid,
                 dut.u_ctrl.status_error);
    end

    // --- Sigma-point generator done ---
    always @(posedge dut.u_sigma_gen.done) begin
        $display("[%0t] SIGMA_GEN: done  sigma_err=%0b", $time, dut.u_sigma_gen.sigma_err);
        $display("  x_vec loaded = [%0.4f, %0.4f, %0.4f, %0.4f, %0.4f]",
                 q2r(dut.u_sigma_gen.x_vec[0]), q2r(dut.u_sigma_gen.x_vec[1]),
                 q2r(dut.u_sigma_gen.x_vec[2]), q2r(dut.u_sigma_gen.x_vec[3]),
                 q2r(dut.u_sigma_gen.x_vec[4]));
        $display("  L_mat diag   = [%0.4f, %0.4f, %0.4f, %0.4f, %0.4f]",
                 q2r(dut.u_sigma_gen.L_mat[0]),  q2r(dut.u_sigma_gen.L_mat[6]),
                 q2r(dut.u_sigma_gen.L_mat[12]), q2r(dut.u_sigma_gen.L_mat[18]),
                 q2r(dut.u_sigma_gen.L_mat[24]));
        dump_mem_region("sigma[0] (chi_0)", `ADDR_SIGMA, 5);
        dump_mem_region("sigma[1] (chi_1)", `ADDR_SIGMA + 5, 5);
    end

    // --- Sigma error set ---
    always @(posedge dut.u_sigma_gen.sigma_err) begin
        $display("[%0t] SIGMA_GEN: *** sigma_err SET ***  chol_j=%0d",
                 $time, dut.u_sigma_gen.chol_j);
        $display("  L_mat diag = [%0.6f, %0.6f, %0.6f, %0.6f, %0.6f]",
                 q2r(dut.u_sigma_gen.L_mat[0]),  q2r(dut.u_sigma_gen.L_mat[6]),
                 q2r(dut.u_sigma_gen.L_mat[12]), q2r(dut.u_sigma_gen.L_mat[18]),
                 q2r(dut.u_sigma_gen.L_mat[24]));
    end

    // --- Predict block done ---
    always @(posedge dut.u_predict.done) begin
        $display("[%0t] PREDICT: done", $time);
        dump_mem_region("x_pred", `ADDR_XPRED, 5);
        dump_matrix("P_pred", `ADDR_PPRED);
    end

    // --- Update block done ---
    always @(posedge dut.u_update.done) begin
        $display("[%0t] UPDATE: done  pass=%0d  upd_err=%0b", $time,
                 dut.u_update.pass, dut.u_update.upd_err);
        $display("  x_work = [%0.6f, %0.6f, %0.6f, %0.6f, %0.6f]",
                 q2r(dut.u_update.x_work[0]), q2r(dut.u_update.x_work[1]),
                 q2r(dut.u_update.x_work[2]), q2r(dut.u_update.x_work[3]),
                 q2r(dut.u_update.x_work[4]));
    end

    // --- Final output valid ---
    always @(posedge dut.u_ctrl.out_valid) begin
        $display("[%0t] WRITEBACK: out_valid  out_x = [%0.6f, %0.6f, %0.6f, %0.6f, %0.6f]",
                 $time,
                 q2r(dut.u_ctrl.out_x[0]), q2r(dut.u_ctrl.out_x[1]),
                 q2r(dut.u_ctrl.out_x[2]), q2r(dut.u_ctrl.out_x[3]),
                 q2r(dut.u_ctrl.out_x[4]));
    end

    // ----------------------------------------------------------
    // Timeout watchdog
    // ----------------------------------------------------------
    initial begin
        #5_000_000;
        $display("WATCHDOG TIMEOUT — simulation exceeded 5 ms");
        $finish;
    end

`else
    // UVM: config_db and run_test() MUST be called at time 0 (UVM 1.1d rule).
    initial begin
        $readmemh("../tb/state_mem_init.memh", dut.u_mem.mem);
        $display("[INIT] State memory loaded from state_mem_init.memh");
        $display("[INIT]   P[0][0]=0x%08h  Q[0][0]=0x%08h  R_gps[0]=0x%08h",
                 dut.u_mem.mem[5], dut.u_mem.mem[30], dut.u_mem.mem[55]);
        rst_n = 0;
        uvm_config_db #(virtual fusion_axi_vif)::set(null, "*", "axi_vif", axi_vif);
        uvm_config_db #(virtual fusion_sensor_vif)::set(null, "*", "sensor_vif", sensor_vif);
        run_test();
    end

    // Reset sequence runs in parallel; drivers wait for clock edges inside run_phase
    initial begin
        rst_n = 0;
        $display("[TB] @%0t rst_n asserted (reset active)", $time);
        repeat (10) @(posedge clk);
        rst_n = 1;
        $display("[TB] @%0t rst_n deasserted (DUT out of reset)", $time);
    end

    initial begin
        repeat(10) #1_000_000_000;
        $display("WATCHDOG TIMEOUT — simulation exceeded 10 s");
        $finish;
    end

    initial begin
        $dumpfile("tb_fusion_ip.vcd");
        $dumpvars(0, tb_fusion_ip);
    end
`endif

endmodule
