// Fusion IP Test Cases - T1 to T8
// Test specifications from UVM_TESTBENCH.md

package fusion_tests_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    import fusion_env_pkg::*;
    import fusion_axi_pkg::*;
    import fusion_sensor_pkg::*;
    import fusion_scoreboard_pkg::*;
    import ukf_mem_backdoor_sv_unit::*;
    import fusion_base_test_pkg::fusion_base_test;
    `include "uvm_macros.svh"
    `include "params.vh"
    
    // Include CSV sequence classes
    `include "../sequences/csv_route_sequence.sv"

    // =====================================================================
    // Helper: push one sensor frame through sensor_vif → DUT FIFOs
    // =====================================================================
    task automatic drive_sensor_frame(
        virtual fusion_sensor_vif vif,
        logic [63:0] gps_data, logic gps_valid,
        logic [95:0] imu_data, logic imu_valid,
        logic [31:0] odom_data, logic odom_valid
    );
        @(posedge vif.clk);
        vif.gps_data   <= gps_data;
        vif.gps_valid  <= gps_valid;
        vif.imu_data   <= imu_data;
        vif.imu_valid  <= imu_valid;
        vif.odom_data  <= odom_data;
        vif.odom_valid <= odom_valid;
        @(posedge vif.clk);
        vif.gps_valid  <= 1'b0;
        vif.imu_valid  <= 1'b0;
        vif.odom_valid <= 1'b0;
        repeat(3) @(posedge vif.clk);
    endtask

    // =====================================================================
    // T1: Sanity Test - Single UKF Cycle
    // =====================================================================
    
    class fusion_sanity_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_sanity_vseq)
        
        function new(string name = "fusion_sanity_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;
            logic [31:0] out_x, out_y, out_psi, out_psidot, out_v;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T1", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            drive_sensor_frame(svif,
                {real_to_dut(1.0), real_to_dut(2.0)}, 1'b1,
                {real_to_dut(0.5), real_to_dut(0.1), 32'h0}, 1'b1,
                real_to_dut(0.5), 1'b1);

            axi_write('h00, 32'h00000001);
            axi_poll_until('h04, 32'h00000002, 32'h00000002, 100000);

            axi_read('h20, out_x);
            axi_read('h24, out_y);
            axi_read('h28, out_v);
            axi_read('h2C, out_psi);
            axi_read('h30, out_psidot);

            `uvm_info("T1_SANITY", 
                $sformatf("Outputs: x=0x%08h y=0x%08h v=0x%08h psi=0x%08h psidot=0x%08h",
                          out_x, out_y, out_v, out_psi, out_psidot), UVM_LOW)
        endtask
    endclass : fusion_sanity_vseq
    
    // =====================================================================
    // T2: Multi-Cycle Test
    // =====================================================================
    
    class fusion_multi_cycle_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_multi_cycle_vseq)
        
        function new(string name = "fusion_multi_cycle_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;
            logic [31:0] out_x, out_y, out_v, out_psi, out_psidot;
            int i;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T2", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            for (i = 0; i < 5; i++) begin
                real gps_x = 1.0 + i * 0.1;
                real gps_y = 2.0 + i * 0.2;
                `uvm_info("T2", $sformatf("Cycle %0d of 5", i+1), UVM_LOW)

                drive_sensor_frame(svif,
                    {real_to_dut(gps_x), real_to_dut(gps_y)}, 1'b1,
                    {real_to_dut(0.5), real_to_dut(0.1), 32'h0}, 1'b1,
                    real_to_dut(0.5), 1'b1);

                axi_write('h00, 32'h00000001);
                axi_poll_until('h04, 32'h00000002, 32'h00000002, 100000);

                axi_read('h20, out_x);
                axi_read('h24, out_y);
                axi_read('h28, out_v);
                axi_read('h2C, out_psi);
                axi_read('h30, out_psidot);

                `uvm_info("T2", $sformatf("Cycle %0d done: x=0x%08h y=0x%08h v=0x%08h psi=0x%08h pd=0x%08h",
                    i+1, out_x, out_y, out_v, out_psi, out_psidot), UVM_LOW)
            end
        endtask
    endclass : fusion_multi_cycle_vseq
    
    // =====================================================================
    // T3: Missing GPS Test
    // =====================================================================
    
    class fusion_missing_gps_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_missing_gps_vseq)
        
        function new(string name = "fusion_missing_gps_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;
            logic [31:0] status;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T3", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            // GPS invalid, only IMU and Odom
            drive_sensor_frame(svif,
                64'h0, 1'b0,
                {real_to_dut(0.5), real_to_dut(0.1), 32'h0}, 1'b1,
                real_to_dut(0.5), 1'b1);

            axi_write('h00, 32'h00000001);
            axi_poll_until('h04, 32'h00000002, 32'h00000002, 100000);
            axi_read('h04, status);

            if (status[2] == 1'b1)
                `uvm_error("T3_ERROR", "Error flag set with missing GPS")
            else
                `uvm_info("T3", "Handled missing GPS correctly", UVM_LOW)
        endtask
    endclass : fusion_missing_gps_vseq
    
    // =====================================================================
    // T4: Interrupt and Clear Test
    // =====================================================================
    
    class fusion_irq_status_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_irq_status_vseq)
        
        function new(string name = "fusion_irq_status_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T4", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            drive_sensor_frame(svif,
                {real_to_dut(1.0), real_to_dut(2.0)}, 1'b1,
                {real_to_dut(0.5), real_to_dut(0.1), 32'h0}, 1'b1,
                real_to_dut(0.5), 1'b1);

            axi_write('h00, 32'h00000001);
            axi_poll_until('h04, 32'h00000002, 32'h00000002, 100000);

            axi_write('h34, 32'h00000001);
            `uvm_info("T4", "Interrupt cleared", UVM_LOW)
        endtask
    endclass : fusion_irq_status_vseq
    
    // =====================================================================
    // T5: Soft Reset Test
    // =====================================================================
    
    class fusion_soft_reset_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_soft_reset_vseq)
        
        function new(string name = "fusion_soft_reset_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T5", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            axi_write('h00, 32'h00000001);
            repeat(10) @(posedge svif.clk);

            axi_write('h00, 32'h00000002);
            axi_poll_until('h04, 32'h00000001, 32'h00000000, 5000);

            `uvm_info("T5", "Soft reset executed", UVM_LOW)
        endtask
    endclass : fusion_soft_reset_vseq
    
    // =====================================================================
    // T6: RAL Bit Bash Test (basic register access)
    // =====================================================================
    
    class fusion_ral_bit_bash_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_ral_bit_bash_vseq)
        
        function new(string name = "fusion_ral_bit_bash_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;
            logic [31:0] test_data[8];
            int i;

            test_data = '{32'hFFFFFFFF, 32'h00000000, 32'hAAAAAAAA, 
                          32'h55555555, 32'hDEADBEEF, 32'hCAFEBABE,
                          32'h12345678, 32'h87654321};

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T6", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            foreach (test_data[i]) begin
                logic [31:0] read_back;
                axi_write('h08, test_data[i]);
                axi_read('h08, read_back);

                if (read_back == test_data[i])
                    `uvm_info("T6", $sformatf("Pattern %0d PASS: 0x%08h", i, test_data[i]), UVM_HIGH)
                else
                    `uvm_error("T6", $sformatf("Pattern %0d FAIL: wrote 0x%08h, read 0x%08h", 
                                             i, test_data[i], read_back))
            end
        endtask
    endclass : fusion_ral_bit_bash_vseq
    
    // =====================================================================
    // T7: Scoreboard Reference Comparison
    // =====================================================================
    
    class fusion_scoreboard_ref_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_scoreboard_ref_vseq)
        
        function new(string name = "fusion_scoreboard_ref_vseq");
            super.new(name);
        endfunction
        
        virtual task body();
            virtual fusion_sensor_vif svif;
            logic [31:0] out_x, out_y, out_v, out_psi, out_psidot;
            int i;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", svif))
                `uvm_fatal("T7", "Cannot get sensor_vif")

            @(posedge svif.rst_n);
            repeat(2) @(posedge svif.clk);

            for (i = 0; i < 3; i++) begin
                real gps_x = 1.0 + i * 0.5;
                real gps_y = 2.0 - i * 0.3;
                real psi = 0.1 * i;

                drive_sensor_frame(svif,
                    {real_to_dut(gps_x), real_to_dut(gps_y)}, 1'b1,
                    {real_to_dut(psi), real_to_dut(0.05), 32'h0}, 1'b1,
                    real_to_dut(1.0), 1'b1);

                axi_write('h00, 32'h00000001);
                axi_poll_until('h04, 32'h00000002, 32'h00000002, 100000);

                axi_read('h20, out_x);
                axi_read('h24, out_y);
                axi_read('h28, out_v);
                axi_read('h2C, out_psi);
                axi_read('h30, out_psidot);
            end

            `uvm_info("T7", "Scoreboard reference test completed", UVM_LOW)
        endtask
    endclass : fusion_scoreboard_ref_vseq
    
    // =====================================================================
    // T8: CSV Route Test — AIS golden data driven
    // Reads golden_stimulus.csv + golden_expected.csv, pushes GT to scoreboard
    // =====================================================================

    class fusion_csv_route_vseq extends base_axi_sequence;
        `uvm_object_utils(fusion_csv_route_vseq)

        string stim_file;
        string expect_file;
        int    poll_timeout;
        int    max_cycles;

        function new(string name = "fusion_csv_route_vseq");
            super.new(name);
            if (!$value$plusargs("STIM_FILE=%s",   stim_file))   stim_file   = "../tb/golden/golden_stimulus.csv";
            if (!$value$plusargs("EXPECT_FILE=%s", expect_file)) expect_file = "../tb/golden/golden_expected.csv";
            // UKF RTL needs ~1e5–1e6 clk per cycle; each poll iter ≈ few clk → use large default
            if (!$value$plusargs("POLL_TO=%d",     poll_timeout)) poll_timeout = 1000000;
            if (!$value$plusargs("MAX_CYCLES=%d",  max_cycles))   max_cycles  = 0;
        endfunction

        virtual task body();
            golden_stimulus_reader stim_reader;
            golden_expected_reader exp_reader;
            sensor_measurement  meas;
            virtual fusion_sensor_vif sensor_vif;
            fusion_scoreboard sb_handle;
            logic [31:0] out_x, out_y, out_v, out_psi, out_psidot;
            logic [31:0] dt_hex_val;
            int stim_count, exp_count, count, i, cyc;
            real sw_est_x, sw_est_y, sw_est_v, sw_est_psi, sw_est_psidot;

            if (!uvm_config_db #(virtual fusion_sensor_vif)::get(
                    null, "", "sensor_vif", sensor_vif))
                `uvm_fatal("T8_CSV", "Cannot get sensor_vif from config_db")

            begin
                uvm_component comp;
                comp = uvm_top.find("uvm_test_top.fusion_environment.scoreboard");
                if (comp != null)
                    $cast(sb_handle, comp);
            end

            `uvm_info("T8_CSV",
                $sformatf("AIS Golden Test: stim=%s  expected=%s  poll_to=%0d  max_cyc=%0d",
                          stim_file, expect_file, poll_timeout, max_cycles), UVM_LOW)

            stim_reader = new(stim_file);
            stim_reader.verbose = 1'b1;
            stim_count = stim_reader.read_file();
            if (stim_count == 0) begin
                `uvm_error("T8_CSV", "No rows read from golden_stimulus.csv")
                return;
            end
            stim_reader.report();

            exp_reader = new(expect_file);
            exp_count = exp_reader.read_file();
            `uvm_info("T8_CSV",
                $sformatf("Expected file: %0d rows loaded (full 5-state golden)", exp_count), UVM_LOW)

            count = stim_count;
            if (max_cycles > 0 && max_cycles < count) count = max_cycles;

            @(posedge sensor_vif.rst_n);
            repeat(2) @(posedge sensor_vif.clk);

            // Match memh/Python x0: poke CTRV state words 0–4 from first golden row, then refresh scoreboard predictor.
            if (stim_reader.init_state_valid) begin
                ukf_state_mem_backdoor::poke_word(`ADDR_X + 0, real_to_dut(stim_reader.init_x0));
                ukf_state_mem_backdoor::poke_word(`ADDR_X + 1, real_to_dut(stim_reader.init_y0));
                ukf_state_mem_backdoor::poke_word(`ADDR_X + 2, real_to_dut(stim_reader.init_speed0));
                ukf_state_mem_backdoor::poke_word(`ADDR_X + 3, real_to_dut(stim_reader.init_heading0));
                ukf_state_mem_backdoor::poke_word(`ADDR_X + 4, real_to_dut(stim_reader.init_yaw_rate0));
                if (sb_handle != null)
                    sb_handle.resync_predictor_from_dut_mem();
                `uvm_info("T8_CSV", "Poked state_mem x[0:4] from golden_stimulus row 0; predictor resynced.", UVM_MEDIUM)
            end

            cyc = 0;
            for (i = 0; i < count; i++) begin
                meas = stim_reader.get_measurement(i);
                if (meas == null) continue;

                // 1. Write dt to AXI REG_DT (0x1C) — get_dt_hex maps 0 → 1.0 s FP32
                dt_hex_val = stim_reader.get_dt_hex(i);
                axi_write(32'h1C, dt_hex_val);

                // 2. Notify scoreboard / predictor (must match DUT dt_effective)
                if (sb_handle != null)
                    sb_handle.set_dt(dt_hex_val);

                // 3. Push full 5-state golden ref to scoreboard
                if (sb_handle != null) begin
                    sw_est_x      = (i < exp_count) ? exp_reader.est_x_arr[i]        : 0.0;
                    sw_est_y      = (i < exp_count) ? exp_reader.est_y_arr[i]        : 0.0;
                    sw_est_v      = (i < exp_count) ? exp_reader.est_speed_arr[i]    : 0.0;
                    sw_est_psi    = (i < exp_count) ? exp_reader.est_heading_arr[i]  : 0.0;
                    sw_est_psidot = (i < exp_count) ? exp_reader.est_yaw_rate_arr[i] : 0.0;
                    sb_handle.push_golden(
                        stim_reader.gt_x_arr[i],  stim_reader.gt_y_arr[i],
                        stim_reader.gps_x_arr[i], stim_reader.gps_y_arr[i],
                        sw_est_x, sw_est_y, sw_est_v, sw_est_psi, sw_est_psidot,
                        dt_hex_val, 1'b1);
                end

                // 4. Drive sensor data
                @(posedge sensor_vif.clk);
                sensor_vif.gps_data  <= meas.gps_data;
                sensor_vif.gps_valid <= meas.gps_valid;
                sensor_vif.imu_data  <= meas.imu_data;
                sensor_vif.imu_valid <= meas.imu_valid;
                sensor_vif.odom_data <= meas.odom_data;
                sensor_vif.odom_valid<= meas.odom_valid;
                @(posedge sensor_vif.clk);
                sensor_vif.gps_valid <= 1'b0;
                sensor_vif.imu_valid <= 1'b0;
                sensor_vif.odom_valid<= 1'b0;
                repeat(3) @(posedge sensor_vif.clk);

                // 5. Trigger UKF
                axi_write(32'h00, 32'h1);
                axi_poll_until(32'h04, 32'h2, 32'h2, poll_timeout);

                // 6. Read all 5 output registers
                axi_read(32'h20, out_x);
                axi_read(32'h24, out_y);
                axi_read(32'h28, out_v);
                axi_read(32'h2C, out_psi);
                axi_read(32'h30, out_psidot);

                // 7. Clear IRQ
                axi_write(32'h34, 32'h1);

                cyc++;
                if ((cyc % 100) == 0 || cyc == 1)
                    `uvm_info("T8_CSV",
                        $sformatf("Progress %0d/%0d  DUT_x=0x%08h DUT_y=0x%08h  GT(%.2f,%.2f)  dt=0x%08h",
                                  cyc, count, out_x, out_y,
                                  stim_reader.gt_x_arr[i], stim_reader.gt_y_arr[i],
                                  dt_hex_val), UVM_LOW)
            end

            `uvm_info("T8_CSV",
                $sformatf("AIS Golden Test done: %0d UKF cycles completed", cyc), UVM_LOW)
        endtask
    endclass : fusion_csv_route_vseq
    
    // =====================================================================
    // Test Classes
    // =====================================================================
    
    class fusion_sanity_test extends fusion_base_test;
        `uvm_component_utils(fusion_sanity_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_sanity_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_sanity_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_multi_cycle_test extends fusion_base_test;
        `uvm_component_utils(fusion_multi_cycle_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_multi_cycle_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_multi_cycle_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_missing_gps_test extends fusion_base_test;
        `uvm_component_utils(fusion_missing_gps_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_missing_gps_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_missing_gps_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_irq_status_test extends fusion_base_test;
        `uvm_component_utils(fusion_irq_status_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_irq_status_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_irq_status_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_soft_reset_test extends fusion_base_test;
        `uvm_component_utils(fusion_soft_reset_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_soft_reset_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_soft_reset_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_ral_bit_bash_test extends fusion_base_test;
        `uvm_component_utils(fusion_ral_bit_bash_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_ral_bit_bash_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_ral_bit_bash_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

    class fusion_scoreboard_ref_test extends fusion_base_test;
        `uvm_component_utils(fusion_scoreboard_ref_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual task run_phase(uvm_phase phase);
            fusion_scoreboard_ref_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_scoreboard_ref_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass
    
    class fusion_csv_route_test extends fusion_base_test;
        `uvm_component_utils(fusion_csv_route_test)
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            fusion_csv_route_vseq vseq;
            phase.raise_objection(this);
            vseq = fusion_csv_route_vseq::type_id::create("vseq");
            vseq.start(fusion_environment.axi_ag.sequencer);
            phase.drop_objection(this);
        endtask
    endclass

endpackage : fusion_tests_pkg

