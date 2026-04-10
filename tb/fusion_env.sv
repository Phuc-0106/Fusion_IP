// Fusion IP UVM Environment Configuration and Base Test

package fusion_env_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    import fusion_ral_pkg::*;
    import fusion_axi_pkg::*;
    import fusion_sensor_pkg::*;
    import fusion_scoreboard_pkg::*;
    import fusion_predictor_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // Environment Configuration
    // =====================================================================
    
    class fusion_env_config extends uvm_object;
        `uvm_object_utils(fusion_env_config)
        
        // Virtual interfaces
        virtual fusion_axi_vif axi_vif;
        virtual fusion_sensor_vif sensor_vif;
        
        // Scoreboard config
        sb_config sb_cfg;
        
        // Test parameters
        int clk_period;              // Clock period in ns
        int poll_timeout;            // Max cycles to poll STATUS
        bit enable_predictor;        // Enable reference model
        bit enable_scoreboard;       // Enable scoreboard
        string csv_route_file;       // CSV file for route test
        int test_seed;               // Random seed
        
        function new(string name = "fusion_env_config");
            super.new(name);
            clk_period = 10;         // 100 MHz
            poll_timeout = 500_000;
            enable_predictor = 1'b1;
            enable_scoreboard = 1'b1;
            csv_route_file = "";
            test_seed = 12345;
        endfunction
    endclass : fusion_env_config
    
    // =====================================================================
    // Fusion Environment
    // =====================================================================
    
    class fusion_env extends uvm_env;
        `uvm_component_utils(fusion_env)
        
        fusion_env_config cfg;
        
        // Register Abstraction Layer
        fusion_reg_block reg_block;
        fusion_reg2axi_adapter reg_adapter;
        
        // Agents
        axi_agent axi_ag;
        sensor_agent sensor_ag;
        
        // Scoreboard
        fusion_scoreboard scoreboard;
        
        // Predictor
        ukf_predictor predictor;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            // Get config from config_db
            if (!uvm_config_db #(fusion_env_config)::get(this, "", "fusion_env_config", cfg))
                cfg = fusion_env_config::type_id::create("cfg");
            
            // Pass virtual interfaces to config_db for agents
            uvm_config_db #(virtual fusion_axi_vif)::set(this, "axi_ag*", "axi_vif", cfg.axi_vif);
            uvm_config_db #(virtual fusion_sensor_vif)::set(this, "sensor_ag*", "sensor_vif", cfg.sensor_vif);
            
            // Set scoreboard config
            if (cfg.sb_cfg == null) begin
                cfg.sb_cfg = sb_config::type_id::create("sb_cfg");
                cfg.sb_cfg.enable_predictor = cfg.enable_predictor;
            end
            uvm_config_db #(sb_config)::set(this, "scoreboard*", "sb_config", cfg.sb_cfg);
            
            // Create RAL register block
            reg_block = fusion_reg_block::type_id::create("reg_block", this);
            reg_block.build();
            
            // Create RAL→AXI adapter
            reg_adapter = fusion_reg2axi_adapter::type_id::create("reg_adapter");
            
            // Create agents
            axi_ag = axi_agent::type_id::create("axi_ag", this);
            sensor_ag = sensor_agent::type_id::create("sensor_ag", this);
            
            // Create scoreboard
            if (cfg.enable_scoreboard) begin
                scoreboard = fusion_scoreboard::type_id::create("scoreboard", this);
            end
            
            // Create predictor
            if (cfg.enable_predictor) begin
                predictor = ukf_predictor::type_id::create("predictor", this);
            end
        endfunction
        
        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            
            // Connect RAL register block to AXI sequencer via adapter
            if (reg_block != null && reg_block.default_map != null && axi_ag.sequencer != null)
                reg_block.default_map.set_sequencer(axi_ag.sequencer, reg_adapter);
            
            // Connect agent monitors to scoreboard analysis imps
            if (scoreboard != null) begin
                axi_ag.monitor.analysis_port.connect(scoreboard.axi_link.imp);
                sensor_ag.monitor.analysis_port.connect(scoreboard.sensor_link.imp);
            end
        endfunction
        
        virtual function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            
            `uvm_info("ENV_EOE", "End of elaboration phase - environment ready", UVM_LOW)
        endfunction
    endclass : fusion_env
    
    // =====================================================================
    // Sequences
    // =====================================================================
    
    // Base Sequence for AXI operations
    class base_axi_sequence extends uvm_sequence #(axi_transaction);
        `uvm_object_utils(base_axi_sequence)
        
        function new(string name = "base_axi_sequence");
            super.new(name);
        endfunction
        
        virtual task body();
            // Override in derived sequences
        endtask
        
        // Helper: AXI write
        virtual task axi_write(logic [31:0] addr, logic [31:0] data);
            axi_transaction trans;
            trans = axi_transaction::type_id::create("trans");
            trans.trans_type = WRITE;
            trans.addr = addr;
            trans.wdata = data;
            start_item(trans);
            finish_item(trans);
        endtask
        
        // Helper: AXI read
        virtual task axi_read(logic [31:0] addr, output logic [31:0] data);
            axi_transaction trans;
            trans = axi_transaction::type_id::create("trans");
            trans.trans_type = READ;
            trans.addr = addr;
            start_item(trans);
            finish_item(trans);
            data = trans.rdata;
        endtask
        
        // Helper: Poll register until condition met
        // Poll STATUS until (data & mask) == expected. fusion_ip_top STATUS: [0]=busy [1]=valid [2]=error
        // UKF can take 1e5+ clock cycles; max_cycles counts AXI read attempts (~10 clk each), not clk cycles.
        virtual task axi_poll_until(
            logic [31:0] addr,
            logic [31:0] mask,
            logic [31:0] expected,
            int max_cycles
        );
            logic [31:0] data;
            int cycle_count = 0;
            
            do begin
                axi_read(addr, data);
                cycle_count++;
                if ((data & 32'h4) != 0) begin
                    `uvm_error("POLL_DUT_ERR",
                        $sformatf("STATUS.error=1 (UKF/sigma failed?) data=0x%08h while waiting valid", data))
                    // Notify scoreboard to skip PRIMARY comparison for this cycle
                    begin
                        uvm_component comp;
                        fusion_scoreboard sb;
                        comp = uvm_top.find("uvm_test_top.fusion_environment.scoreboard");
                        if (comp != null && $cast(sb, comp))
                            sb.set_dut_error(1);
                    end
                    break;
                end
                if (cycle_count >= max_cycles) begin
                    `uvm_error("POLL_TIMEOUT", 
                              $sformatf("Poll timeout: addr=0x%08h, expected=0x%08h (mask=0x%08h) after %0d reads — increase +POLL_TO (UKF needs many cycles)",
                                       addr, expected, mask, max_cycles))
                    break;
                end
            end while ((data & mask) != expected);
        endtask
    endclass : base_axi_sequence
    
    // Base Sequence for sensor data
    class base_sensor_sequence extends uvm_sequence #(sensor_measurement);
        `uvm_object_utils(base_sensor_sequence)
        
        function new(string name = "base_sensor_sequence");
            super.new(name);
        endfunction
        
        virtual task body();
            // Override in derived sequences
        endtask
        
        // Helper: Send sensor measurement
        virtual task send_measurement(
            logic [63:0] gps_data,
            logic        gps_valid,
            logic [95:0] imu_data,
            logic        imu_valid,
            logic [31:0] odom_data,
            logic        odom_valid
        );
            sensor_measurement meas;
            meas = sensor_measurement::type_id::create("meas");
            meas.gps_data = gps_data;
            meas.gps_valid = gps_valid;
            meas.imu_data = imu_data;
            meas.imu_valid = imu_valid;
            meas.odom_data = odom_data;
            meas.odom_valid = odom_valid;
            start_item(meas);
            finish_item(meas);
        endtask
    endclass : base_sensor_sequence

endpackage : fusion_env_pkg

