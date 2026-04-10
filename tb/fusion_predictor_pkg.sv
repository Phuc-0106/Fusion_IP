// =====================================================================
// Fusion IP Reference Model/Predictor Package
// =====================================================================

package fusion_predictor_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"
    
    // =====================================================================
    // UKF Prediction State
    // =====================================================================
    
    typedef struct packed {
        logic [31:0] x_pos;      // X position (m, Q8.24)
        logic [31:0] y_pos;      // Y position (m, Q8.24)
        logic [31:0] psi;        // Heading angle (rad, Q8.24)
        logic [31:0] v;          // Velocity (m/s, Q8.24)
        logic [31:0] psi_dot;    // Yaw rate (rad/s, Q8.24)
    } ukf_state_t;
    
    // =====================================================================
    // UKF Reference Model / Predictor
    // =====================================================================
    
    class ukf_predictor extends uvm_subscriber #(uvm_sequence_item);
        `uvm_component_utils(ukf_predictor)
        
        ukf_state_t predicted_state;
        ukf_state_t previous_state;
        
        // Prediction statistics
        int predictions_made;
        
        // Configuration handle (if needed)
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
            predictions_made = 0;
            predicted_state = '0;
            previous_state = '0;
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
        endfunction
        
        virtual function void write(uvm_sequence_item t);
            // Stub: Implement UKF prediction algorithm
            // - Take sensor measurements (GPS, IMU, Odom)
            // - Update predicted state using kinematic model
            // - Store for comparison with DUT output
            
            predictions_made++;
            previous_state = predicted_state;
            
            // Placeholder: Simple velocity integration
            // Real implementation would include full UKF math
        endfunction
        
        function ukf_state_t get_predicted_state();
            return predicted_state;
        endfunction
        
        virtual function void report_phase(uvm_phase phase);
            `uvm_info("PRED_REPORT",
                $sformatf("Predictions made: %d", predictions_made),
                UVM_MEDIUM)
        endfunction
    endclass : ukf_predictor
    
endpackage : fusion_predictor_pkg
