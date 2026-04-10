// Fusion IP UVM Package - Basic Definitions
// Defines enums, structs, and constants for verification

package fusion_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // AXI Transaction Definitions
    // =====================================================================
    
    typedef enum {
        WRITE,
        READ
    } axi_trans_type_e;
    
    typedef enum logic [31:0] {
        OKAY   = 32'h00,
        EXOKAY = 32'h01,
        SLVERR = 32'h10,
        DECERR = 32'h11
    } axi_resp_e;
    
    class axi_transaction extends uvm_sequence_item;
        rand axi_trans_type_e trans_type;
        rand logic [31:0]     addr;
        rand logic [31:0]     wdata;
        logic [31:0]          rdata;
        logic [3:0]           wstrb;
        axi_resp_e            resp;
        int                   delay;
        
        `uvm_object_utils_begin(axi_transaction)
            `uvm_field_enum(axi_trans_type_e, trans_type, UVM_ALL_ON)
            `uvm_field_int(addr, UVM_ALL_ON)
            `uvm_field_int(wdata, UVM_ALL_ON)
            `uvm_field_int(rdata, UVM_ALL_ON)
            `uvm_field_int(wstrb, UVM_ALL_ON)
            `uvm_field_enum(axi_resp_e, resp, UVM_ALL_ON)
            `uvm_field_int(delay, UVM_ALL_ON)
        `uvm_object_utils_end
        
        function new(string name = "axi_transaction");
            super.new(name);
            wstrb = 4'hF;
            delay = 0;
            resp = OKAY;
        endfunction
    endclass : axi_transaction
    
    // =====================================================================
    // Sensor Transaction Definitions
    // =====================================================================
    
    class sensor_measurement extends uvm_sequence_item;
        // Match fusion_ip_top: GPS [63:32]=x, [31:0]=y; IMU [95:64]=psi, [63:32]=psidot, [31:0]=pad
        rand logic [63:0] gps_data;
        rand logic        gps_valid;
        rand logic [95:0] imu_data;
        rand logic        imu_valid;
        rand logic [31:0] odom_data;
        rand logic        odom_valid;
        rand int          duration;      // Clock cycles to hold
        
        `uvm_object_utils_begin(sensor_measurement)
            `uvm_field_int(gps_data, UVM_ALL_ON)
            `uvm_field_int(gps_valid, UVM_ALL_ON)
            `uvm_field_int(imu_data, UVM_ALL_ON)
            `uvm_field_int(imu_valid, UVM_ALL_ON)
            `uvm_field_int(odom_data, UVM_ALL_ON)
            `uvm_field_int(odom_valid, UVM_ALL_ON)
            `uvm_field_int(duration, UVM_ALL_ON)
        `uvm_object_utils_end
        
        constraint duration_ct { duration inside {[1:10]}; }
        
        function new(string name = "sensor_measurement");
            super.new(name);
            gps_valid = 1'b1;
            imu_valid = 1'b1;
            odom_valid = 1'b1;
            duration = 1;
        endfunction
    endclass : sensor_measurement
    
    // =====================================================================
    // Fusion Registers - Address Map (from AXI slave MMIO)
    // =====================================================================
    
    typedef enum logic [7:0] {
        CTRL_ADDR     = 8'h00,   // Control register
        STATUS_ADDR   = 8'h04,   // Status register
        GPS_X_ADDR    = 8'h08,   // GPS X position
        GPS_Y_ADDR    = 8'h0C,   // GPS Y position
        IMU_PSI_ADDR  = 8'h10,   // IMU angle psi
        IMU_PSIDOT_ADDR = 8'h14, // IMU angular velocity
        ODOM_V_ADDR   = 8'h18,   // Odometry velocity
        OUT_X_ADDR    = 8'h20,   // Output X
        OUT_Y_ADDR    = 8'h24,   // Output Y
        OUT_V_ADDR    = 8'h28,   // Output velocity
        OUT_PSI_ADDR  = 8'h2C,   // Output psi
        OUT_PSIDOT_ADDR = 8'h30, // Output psi_dot
        IRQ_CLR_ADDR  = 8'h34    // Interrupt clear
    } fusion_reg_addr_e;
    
    // Control Register Bits
    typedef struct packed {
        logic [31:2] reserved;
        logic        soft_reset;    // [1] - soft reset
        logic        start;         // [0] - start UKF cycle
    } ctrl_reg_t;
    
    // Status Register Bits
    typedef struct packed {
        logic [31:3] reserved;
        logic        error_flag;    // [2] - error/timeout
        logic        valid;         // [1] - output valid
        logic        busy;          // [0] - pipeline busy
    } status_reg_t;
    
    // =====================================================================
    // Fixed-Point / Float Utilities
    // =====================================================================
    
    typedef logic signed [31:0] fixed32_q824_t;
    
    function automatic fixed32_q824_t double_to_q824(real d);
        return $rtoi(d * (2**24));
    endfunction
    
    function automatic real q824_to_double(fixed32_q824_t q);
        return real'(q) / (2**24);
    endfunction

    // IEEE 754 single-precision ↔ real (for USE_FP32 mode)
    function automatic logic [31:0] double_to_fp32(real d);
        return $shortrealtobits(shortreal'(d));
    endfunction

    function automatic real fp32_to_double(logic [31:0] bits);
        return real'($bitstoshortreal(bits));
    endfunction

    // Unified helpers — IEEE-754 single-precision (FP32 only)
    function automatic logic [31:0] real_to_dut(real d);
        return double_to_fp32(d);
    endfunction
    function automatic real dut_to_real(logic [31:0] bits);
        return fp32_to_double(bits);
    endfunction
    
    // =====================================================================
    // Scoreboard Expected Values
    // =====================================================================
    
    // State order matches RTL: [x, y, v, ψ, ψ̇]
    class ukf_output extends uvm_object;
        real x;              // Estimated X position   (state[0])
        real y;              // Estimated Y position   (state[1])
        real v;              // Estimated velocity     (state[2])
        real psi;            // Estimated heading      (state[3])
        real psi_dot;        // Estimated yaw rate     (state[4])
        
        `uvm_object_utils_begin(ukf_output)
            `uvm_field_real(x, UVM_ALL_ON)
            `uvm_field_real(y, UVM_ALL_ON)
            `uvm_field_real(psi, UVM_ALL_ON)
            `uvm_field_real(psi_dot, UVM_ALL_ON)
            `uvm_field_real(v, UVM_ALL_ON)
        `uvm_object_utils_end
        
        function new(string name = "ukf_output");
            super.new(name);
        endfunction
        
        function string convert2string();
            return $sformatf("UKF_OUT[x=%.6f, y=%.6f, psi=%.6f, psidot=%.6f, v=%.6f]",
                            x, y, psi, psi_dot, v);
        endfunction
    endclass : ukf_output

endpackage : fusion_pkg

