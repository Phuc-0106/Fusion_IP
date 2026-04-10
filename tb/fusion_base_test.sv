// =====================================================================
// Fusion IP Base Test Class
// =====================================================================

package fusion_base_test_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    import fusion_env_pkg::*;
    import fusion_scoreboard_pkg::*;
    import fusion_predictor_pkg::*;
    `include "uvm_macros.svh"

class fusion_base_test extends uvm_test;
    `uvm_component_utils(fusion_base_test)
    
    fusion_env_config env_cfg;
    fusion_env        fusion_environment;
    
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        
        env_cfg = fusion_env_config::type_id::create("env_cfg");
        
        void'($value$plusargs("clk_period=%d", env_cfg.clk_period));
        void'($value$plusargs("timeout=%d", env_cfg.poll_timeout));
        void'($value$plusargs("csv=%s", env_cfg.csv_route_file));
        void'($value$plusargs("seed=%d", env_cfg.test_seed));
        
        if (!uvm_config_db #(virtual fusion_axi_vif)::get(this, "", "axi_vif", env_cfg.axi_vif))
            `uvm_fatal("FUSION_TEST", "config_db missing axi_vif (set in tb before run_test)")
        if (!uvm_config_db #(virtual fusion_sensor_vif)::get(this, "", "sensor_vif", env_cfg.sensor_vif))
            `uvm_fatal("FUSION_TEST", "config_db missing sensor_vif (set in tb before run_test)")
        
        if (!uvm_config_db #(sb_config)::get(this, "", "sb_config", env_cfg.sb_cfg)) begin
            env_cfg.sb_cfg = sb_config::type_id::create("sb_cfg");
            uvm_config_db #(sb_config)::set(this, "*", "sb_config", env_cfg.sb_cfg);
        end
        
        uvm_config_db #(fusion_env_config)::set(this, "*", "fusion_env_config", env_cfg);
        
        fusion_environment = fusion_env::type_id::create("fusion_environment", this);
    endfunction
    
    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
    endfunction
    
    virtual task run_phase(uvm_phase phase);
        // Default: No stimulus (override in derived test classes)
    endtask
    
    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("FUSION_TEST_REPORT", "Base test execution completed", UVM_MEDIUM)
    endfunction
    
endclass : fusion_base_test
endpackage : fusion_base_test_pkg
