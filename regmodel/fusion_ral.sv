// Fusion IP RAL - Register Block
// Registers: CTRL, STATUS, sensor inputs, UKF outputs, IRQ_CLR

package fusion_ral_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // Register Fields
    // =====================================================================
    
    class ctrl_reg_fld_start extends uvm_reg_field;
        `uvm_object_utils(ctrl_reg_fld_start)
        function new(string name = "start");
            super.new(name);
        endfunction
    endclass
    
    class ctrl_reg_fld_soft_reset extends uvm_reg_field;
        `uvm_object_utils(ctrl_reg_fld_soft_reset)
        function new(string name = "soft_reset");
            super.new(name);
        endfunction
    endclass
    
    class status_reg_fld_busy extends uvm_reg_field;
        `uvm_object_utils(status_reg_fld_busy)
        function new(string name = "busy");
            super.new(name);
        endfunction
    endclass
    
    class status_reg_fld_valid extends uvm_reg_field;
        `uvm_object_utils(status_reg_fld_valid)
        function new(string name = "valid");
            super.new(name);
        endfunction
    endclass
    
    class status_reg_fld_error extends uvm_reg_field;
        `uvm_object_utils(status_reg_fld_error)
        function new(string name = "error");
            super.new(name);
        endfunction
    endclass
    
    // =====================================================================
    // Registers
    // =====================================================================
    
    class ctrl_reg extends uvm_reg;
        `uvm_object_utils(ctrl_reg)
        
        ctrl_reg_fld_start       start;
        ctrl_reg_fld_soft_reset  soft_reset;
        
        function new(string name = "ctrl_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            start = ctrl_reg_fld_start::type_id::create("start");
            start.configure(this, 1, 0, .volatile(0), .access("RW"));
            
            soft_reset = ctrl_reg_fld_soft_reset::type_id::create("soft_reset");
            soft_reset.configure(this, 1, 1, .volatile(0), .access("RW"));
        endfunction
    endclass : ctrl_reg
    
    class status_reg extends uvm_reg;
        `uvm_object_utils(status_reg)
        
        status_reg_fld_busy  busy;
        status_reg_fld_valid valid;
        status_reg_fld_error error;
        
        function new(string name = "status_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            busy = status_reg_fld_busy::type_id::create("busy");
            busy.configure(this, 1, 0, .volatile(1), .access("RO"));
            
            valid = status_reg_fld_valid::type_id::create("valid");
            valid.configure(this, 1, 1, .volatile(1), .access("RO"));
            
            error = status_reg_fld_error::type_id::create("error");
            error.configure(this, 1, 2, .volatile(1), .access("RO"));
        endfunction
    endclass : status_reg
    
    class sensor_reg extends uvm_reg;
        `uvm_object_utils(sensor_reg)
        
        uvm_reg_field data;
        
        function new(string name = "sensor_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            data = uvm_reg_field::type_id::create("data");
            data.configure(this, 32, 0, .volatile(0), .access("RW"));
        endfunction
    endclass : sensor_reg
    
    class output_reg extends uvm_reg;
        `uvm_object_utils(output_reg)
        
        uvm_reg_field data;
        
        function new(string name = "output_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            data = uvm_reg_field::type_id::create("data");
            data.configure(this, 32, 0, .volatile(1), .access("RO"));
        endfunction
    endclass : output_reg
    
    class irq_clr_reg extends uvm_reg;
        `uvm_object_utils(irq_clr_reg)
        
        uvm_reg_field clr;
        
        function new(string name = "irq_clr_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            clr = uvm_reg_field::type_id::create("clr");
            clr.configure(this, 32, 0, .volatile(0), .access("WO"));
        endfunction
    endclass : irq_clr_reg
    
    // =====================================================================
    // Register Block
    // =====================================================================
    
    class fusion_reg_block extends uvm_reg_block;
        `uvm_object_utils(fusion_reg_block)
        
        // Registers
        ctrl_reg        ctrl;
        status_reg      status;
        sensor_reg      gps_x;
        sensor_reg      gps_y;
        sensor_reg      imu_psi;
        sensor_reg      imu_psi_dot;
        sensor_reg      odom_v;
        output_reg      out_x;
        output_reg      out_y;
        output_reg      out_psi;
        output_reg      out_psi_dot;
        output_reg      out_v;
        irq_clr_reg     irq_clr;
        
        function new(string name = "fusion_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction
        
        virtual function void build();
            // Create registers
            ctrl = ctrl_reg::type_id::create("ctrl");
            ctrl.configure(this, null);
            ctrl.build();
            
            status = status_reg::type_id::create("status");
            status.configure(this, null);
            status.build();
            
            gps_x = sensor_reg::type_id::create("gps_x");
            gps_x.configure(this, null);
            gps_x.build();
            
            gps_y = sensor_reg::type_id::create("gps_y");
            gps_y.configure(this, null);
            gps_y.build();
            
            imu_psi = sensor_reg::type_id::create("imu_psi");
            imu_psi.configure(this, null);
            imu_psi.build();
            
            imu_psi_dot = sensor_reg::type_id::create("imu_psi_dot");
            imu_psi_dot.configure(this, null);
            imu_psi_dot.build();
            
            odom_v = sensor_reg::type_id::create("odom_v");
            odom_v.configure(this, null);
            odom_v.build();
            
            out_x = output_reg::type_id::create("out_x");
            out_x.configure(this, null);
            out_x.build();
            
            out_y = output_reg::type_id::create("out_y");
            out_y.configure(this, null);
            out_y.build();
            
            out_psi = output_reg::type_id::create("out_psi");
            out_psi.configure(this, null);
            out_psi.build();
            
            out_psi_dot = output_reg::type_id::create("out_psi_dot");
            out_psi_dot.configure(this, null);
            out_psi_dot.build();
            
            out_v = output_reg::type_id::create("out_v");
            out_v.configure(this, null);
            out_v.build();
            
            irq_clr = irq_clr_reg::type_id::create("irq_clr");
            irq_clr.configure(this, null);
            irq_clr.build();
            
            // Add registers to block with address map
            this.default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);
            this.default_map.add_reg(ctrl,       'h00, .access("RW"));
            this.default_map.add_reg(status,     'h04, .access("RO"));
            this.default_map.add_reg(gps_x,      'h08, .access("RW"));
            this.default_map.add_reg(gps_y,      'h0C, .access("RW"));
            this.default_map.add_reg(imu_psi,    'h10, .access("RW"));
            this.default_map.add_reg(imu_psi_dot,'h14, .access("RW"));
            this.default_map.add_reg(odom_v,     'h18, .access("RW"));
            this.default_map.add_reg(out_x,      'h20, .access("RO"));
            this.default_map.add_reg(out_y,      'h24, .access("RO"));
            this.default_map.add_reg(out_v,      'h28, .access("RO"));
            this.default_map.add_reg(out_psi,    'h2C, .access("RO"));
            this.default_map.add_reg(out_psi_dot,'h30, .access("RO"));
            this.default_map.add_reg(irq_clr,    'h34, .access("WO"));
            
            // Lock the address map
            this.lock_model();
        endfunction
    endclass : fusion_reg_block

endpackage : fusion_ral_pkg

