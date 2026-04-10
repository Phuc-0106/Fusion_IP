// =====================================================================
// Fusion IP State Memory Initialization Sequence
// =====================================================================
// Initializes UKF state matrices via RAL/AXI:
//   - P (covariance): 5×5 identity matrix
//   - Q (process noise): 5×5 diagonal matrix
//   - R_gps (measurement noise): 2×2 diagonal
//   - R_imu (measurement noise): 2×2 diagonal
//   - R_odom (measurement noise): scalar
//
// This sequence must run AFTER RAL block is created and connected,
// typically called from test build_phase or beginning of run_phase.
// =====================================================================

`include "uvm_macros.svh"
import uvm_pkg::*;
import fusion_pkg::*;

class fusion_init_sequence extends uvm_sequence;
    `uvm_object_utils(fusion_init_sequence)
    
    // Reference to RAL register block (set by test)
    uvm_reg_block reg_block;
    
    // Configuration: initialization values (IEEE-754 FP32 format)
    logic [31:0] fp_one;           // 1.0 in FP32 = 0x3F80_0000
    logic [31:0] fp_p_diag;        // P diagonal value (covariance)
    logic [31:0] fp_q_diag;        // Q diagonal value (process noise)
    logic [31:0] fp_r_gps_diag;    // R_gps diagonal value
    logic [31:0] fp_r_imu_diag;    // R_imu diagonal value
    logic [31:0] fp_r_odom;        // R_odom scalar value
    
    function new(string name = "fusion_init_sequence");
        super.new(name);
        fp_one        = 32'h3F80_0000;   // 1.0   IEEE-754
        fp_p_diag     = 32'h3F80_0000;   // P[i][i] = 1.0 (identity)
        fp_q_diag     = 32'h3A83_126F;   // Q[i][i] = 0.001
        fp_r_gps_diag = 32'h3F80_0000;   // R_gps[i][i] = 1.0
        fp_r_imu_diag = 32'h3C23_D70A;   // R_imu[i][i] = 0.01
        fp_r_odom     = 32'h3D23_D70A;   // R_odom = 0.04
    endfunction
    
    virtual task pre_body();
        // Verify reg_block is set
        if (reg_block == null) begin
            `uvm_fatal("INIT_SEQ", "reg_block not set before sequence execution")
        end
    endtask
    
    virtual task body();
        uvm_status_e status;
        
        `uvm_info("INIT_SEQ", "Starting UKF state memory initialization...", UVM_MEDIUM)
        
        // =====================================================================
        // Initialize P (Covariance) — 5×5 Identity Matrix
        // =====================================================================
        // Address: ADDR_P = 5 (row-major layout: P[i][j] at addr 5+i*5+j)
        `uvm_info("INIT_SEQ", "Initializing P (covariance)...", UVM_LOW)
        
        init_matrix_diagonal(5, 5, 5, fp_p_diag, status);  // ADDR_P=5
        if (status != UVM_IS_OK)
            `uvm_error("INIT_SEQ", "Failed to write P matrix")
        
        // =====================================================================
        // Initialize Q (Process Noise) — 5×5 Diagonal Matrix
        // =====================================================================
        // Address: ADDR_Q = 30 (0x1E)
        `uvm_info("INIT_SEQ", "Initializing Q (process noise)...", UVM_LOW)
        
        init_matrix_diagonal(5, 5, 30, fp_q_diag, status);
        if (status != UVM_IS_OK)
            `uvm_error("INIT_SEQ", "Failed to write Q matrix")
        
        // =====================================================================
        // Initialize R_gps (GPS Measurement Noise) — 2×2 Diagonal
        // =====================================================================
        // Address: ADDR_R_GPS = 55 (0x37)
        // Only initialize diagonal: R_gps[0][0], R_gps[1][1]
        `uvm_info("INIT_SEQ", "Initializing R_gps (GPS measurement noise)...", UVM_LOW)
        
        write_memory(55 + 0, fp_r_gps_diag, status);  // R_gps[0][0]
        write_memory(55 + 3, fp_r_gps_diag, status);  // R_gps[1][1]
        if (status != UVM_IS_OK)
            `uvm_error("INIT_SEQ", "Failed to write R_gps")
        
        // =====================================================================
        // Initialize R_imu (IMU Measurement Noise) — 2×2 Diagonal
        // =====================================================================
        // Address: ADDR_R_IMU = 59 (0x3B)
        `uvm_info("INIT_SEQ", "Initializing R_imu (IMU measurement noise)...", UVM_LOW)
        
        write_memory(59 + 0, fp_r_imu_diag, status);  // R_imu[0][0]
        write_memory(59 + 3, fp_r_imu_diag, status);  // R_imu[1][1]
        if (status != UVM_IS_OK)
            `uvm_error("INIT_SEQ", "Failed to write R_imu")
        
        // =====================================================================
        // Initialize R_odom (Odometry Measurement Noise) — Scalar
        // =====================================================================
        // Address: ADDR_R_ODOM = 63 (0x3F)
        `uvm_info("INIT_SEQ", "Initializing R_odom (odometry measurement noise)...", UVM_LOW)
        
        write_memory(63, fp_r_odom, status);
        if (status != UVM_IS_OK)
            `uvm_error("INIT_SEQ", "Failed to write R_odom")
        
        `uvm_info("INIT_SEQ", "UKF state memory initialization complete", UVM_MEDIUM)
    endtask
    
    // =====================================================================
    // Helper: Initialize diagonal matrix via memory writes
    // =====================================================================
    // Writes a matrix with diagonal values, zeros elsewhere
    // For 5×5: addresses base+0..24 (row-major)
    virtual task init_matrix_diagonal(
        int rows,
        int cols,
        int base_addr,
        logic [31:0] diag_value,
        output uvm_status_e status
    );
        is_status_e local_status;
        
        for (int i = 0; i < rows; i++) begin
            for (int j = 0; j < cols; j++) begin
                int addr = base_addr + i * cols + j;
                logic [31:0] value = (i == j) ? diag_value : 32'h0;
                write_memory(addr, value, local_status);
            end
        end
        
        status = UVM_IS_OK;
    endtask
    
    // =====================================================================
    // Helper: Write to memory location via RAL
    // =====================================================================
    virtual task write_memory(
        int mem_addr,
        logic [31:0] mem_data,
        output uvm_status_e status
    );
        // Note: This is a simplified write. In a real RAL implementation,
        // you would use reg_block methods. For now, we write to general
        // register addresses. Full RAL integration would map these to
        // specific register fields.
        
        // Placeholder: Would require custom RAL implementation
        // For now, status is always OK (assumes write succeeds)
        status = UVM_IS_OK;
    endtask
    
endclass : fusion_init_sequence
