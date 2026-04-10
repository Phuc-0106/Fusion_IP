// Sensor Driver and Monitor for Fusion IP
// Handles GPS, IMU, and Odometry sensor data

package fusion_sensor_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // Sensor Driver
    // =====================================================================
    
    class sensor_driver extends uvm_driver #(sensor_measurement);
        `uvm_component_utils(sensor_driver)
        
        virtual fusion_sensor_vif vif;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(this, "", "sensor_vif", vif))
                `uvm_fatal("SENSOR_DRV", "Cannot get Sensor VIF from config_db")
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            sensor_measurement meas;
            
            reset_signals();

            @(posedge vif.rst_n);
            repeat(2) @(posedge vif.clk);
            
            forever begin
                seq_item_port.get_next_item(meas);
                drive_measurement(meas);
                seq_item_port.item_done();
            end
        endtask
        
        virtual task reset_signals();
            vif.gps_data   <= '0;
            vif.gps_valid  <= 1'b0;
            vif.imu_data   <= '0;
            vif.imu_valid  <= 1'b0;
            vif.odom_data  <= '0;
            vif.odom_valid <= 1'b0;
        endtask
        
        virtual task drive_measurement(sensor_measurement meas);
            vif.gps_data   <= meas.gps_data;
            vif.gps_valid  <= meas.gps_valid;
            vif.imu_data   <= meas.imu_data;
            vif.imu_valid  <= meas.imu_valid;
            vif.odom_data  <= meas.odom_data;
            vif.odom_valid <= meas.odom_valid;
            
            repeat(meas.duration) @(posedge vif.clk);
            
            vif.gps_valid  <= 1'b0;
            vif.imu_valid  <= 1'b0;
            vif.odom_valid <= 1'b0;
            
            @(posedge vif.clk);
        endtask
    endclass : sensor_driver
    
    // =====================================================================
    // Sensor Monitor
    // =====================================================================
    
    class sensor_monitor extends uvm_monitor;
        `uvm_component_utils(sensor_monitor)
        
        virtual fusion_sensor_vif vif;
        uvm_analysis_port #(sensor_measurement) analysis_port;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            analysis_port = new("analysis_port", this);
            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(this, "", "sensor_vif", vif))
                `uvm_fatal("SENSOR_MON", "Cannot get Sensor VIF from config_db")
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            forever begin
                sensor_measurement meas;
                
                @(posedge vif.clk iff (vif.gps_valid || vif.imu_valid || vif.odom_valid));
                
                meas = sensor_measurement::type_id::create("meas");
                meas.gps_data = vif.gps_data;
                meas.gps_valid = vif.gps_valid;
                meas.imu_data = vif.imu_data;
                meas.imu_valid = vif.imu_valid;
                meas.odom_data = vif.odom_data;
                meas.odom_valid = vif.odom_valid;
                meas.duration = 1;
                
                analysis_port.write(meas);
            end
        endtask
    endclass : sensor_monitor
    
    // =====================================================================
    // Sensor Sequencer
    // =====================================================================
    
    class sensor_sequencer extends uvm_sequencer #(sensor_measurement);
        `uvm_component_utils(sensor_sequencer)
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass : sensor_sequencer
    
    // =====================================================================
    // Sensor Agent
    // =====================================================================
    
    class sensor_agent extends uvm_agent;
        `uvm_component_utils(sensor_agent)
        
        sensor_driver      driver;
        sensor_monitor     monitor;
        sensor_sequencer   sequencer;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            sequencer = sensor_sequencer::type_id::create("sequencer", this);
            driver = sensor_driver::type_id::create("driver", this);
            monitor = sensor_monitor::type_id::create("monitor", this);
        endfunction
        
        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass : sensor_agent

endpackage : fusion_sensor_pkg
