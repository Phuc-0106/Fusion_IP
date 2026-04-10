// =====================================================================
// Fusion IP Scoreboard Package — DEPRECATED STUB
// Use fusion_scoreboard.sv (full package + fusion_scoreboard) in compile.f
// =====================================================================

package fusion_scoreboard_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"
    
    // =====================================================================
    // Scoreboard Configuration
    // =====================================================================
    
    class sb_config extends uvm_object;
        `uvm_object_utils(sb_config)
        
        bit enable_coverage;
        bit enable_prediction;
        bit enable_predictor;
        int prediction_tolerance;
        
        function new(string name = "sb_config");
            super.new(name);
            enable_coverage = 1;
            enable_prediction = 1;
            enable_predictor = 1;
            prediction_tolerance = 10;
        endfunction
    endclass : sb_config
    
    // =====================================================================
    // Scoreboard
    // =====================================================================
    
    class fusion_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(fusion_scoreboard)
        
        uvm_tlm_analysis_fifo #(uvm_sequence_item) sensor_fifo;
        uvm_tlm_analysis_fifo #(uvm_sequence_item) axi_fifo;
        
        uvm_analysis_imp #(uvm_sequence_item, fusion_scoreboard) axi_port;
        uvm_analysis_imp #(uvm_sequence_item, fusion_scoreboard) sensor_port;
        
        sb_config sb_cfg;
        
        int num_compared;
        int num_mismatches;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
            num_compared = 0;
            num_mismatches = 0;
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            sensor_fifo = new("sensor_fifo", this);
            axi_fifo = new("axi_fifo", this);
            
            axi_port = new("axi_port", this);
            sensor_port = new("sensor_port", this);
            
            if (!uvm_config_db #(sb_config)::get(this, "", "sb_config", sb_cfg))
                sb_cfg = sb_config::type_id::create("sb_cfg");
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            // Scoreboard comparison logic
        endtask
        
        virtual function void report_phase(uvm_phase phase);
            `uvm_info("SCBD_REPORT", 
                $sformatf("Transactions: %d | Mismatches: %d",
                num_compared, num_mismatches), UVM_MEDIUM)
        endfunction
    endclass : fusion_scoreboard
    
endpackage : fusion_scoreboard_pkg
