// AXI4-Lite Driver for Fusion IP
// Drives AXI4-Lite transactions to the DUT

package fusion_axi_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"

    // =====================================================================
    // AXI Driver
    // =====================================================================
    
    class axi_driver extends uvm_driver #(axi_transaction);
        `uvm_component_utils(axi_driver)
        
        virtual fusion_axi_vif vif;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual fusion_axi_vif)::get(this, "", "axi_vif", vif))
                `uvm_fatal("AXI_DRV", "Cannot get AXI VIF from config_db")
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            axi_transaction trans;
            
            reset_signals();
            @(posedge vif.rst_n);
            repeat(2) @(posedge vif.clk);
            
            forever begin
                seq_item_port.get_next_item(trans);
                drive_transaction(trans);
                seq_item_port.item_done();
            end
        endtask
        
        virtual task reset_signals();
            vif.awaddr  <= 32'h0;
            vif.awvalid <= 1'b0;
            vif.wdata   <= 32'h0;
            vif.wstrb   <= 4'h0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.araddr  <= 32'h0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;
        endtask
        
        virtual task drive_transaction(axi_transaction trans);
            if (trans.delay > 0)
                repeat(trans.delay) @(posedge vif.clk);
            
            case (trans.trans_type)
                WRITE: drive_write_transaction(trans);
                READ:  drive_read_transaction(trans);
            endcase
        endtask
        
        virtual task drive_write_transaction(axi_transaction trans);
            vif.awaddr  <= trans.addr;
            vif.awvalid <= 1'b1;
            vif.wdata   <= trans.wdata;
            vif.wstrb   <= (trans.wstrb != '0) ? trans.wstrb : 4'hF;
            vif.wvalid  <= 1'b1;
            vif.bready  <= 1'b1;

            @(posedge vif.clk);
            while (!(vif.awready && vif.wready)) @(posedge vif.clk);

            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;

            begin : BVALID_WAIT
                int to = 0;
                @(posedge vif.clk);
                while (!vif.bvalid) begin
                    to++;
                    if (to >= 2000) begin
                        $display("[AXI_DRV] ERROR: bvalid timeout addr=0x%08h", trans.addr);
                        break;
                    end
                    @(posedge vif.clk);
                end
            end

            trans.resp  = axi_resp_e'(vif.bresp);
            vif.bready  <= 1'b0;
            @(posedge vif.clk);
        endtask
        
        virtual task drive_read_transaction(axi_transaction trans);
            vif.araddr  <= trans.addr;
            vif.arvalid <= 1'b1;
            
            @(posedge vif.clk);
            while (!vif.arready) @(posedge vif.clk);
            vif.arvalid <= 1'b0;
            
            vif.rready <= 1'b1;
            @(posedge vif.clk);
            while (!vif.rvalid) @(posedge vif.clk);
            
            trans.rdata = vif.rdata;
            trans.resp = axi_resp_e'(vif.rresp);
            vif.rready <= 1'b0;
            @(posedge vif.clk);
        endtask
    endclass : axi_driver
    
    // =====================================================================
    // AXI Monitor
    // =====================================================================
    
    class axi_monitor extends uvm_monitor;
        `uvm_component_utils(axi_monitor)
        
        virtual fusion_axi_vif vif;
        uvm_analysis_port #(axi_transaction) analysis_port;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            analysis_port = new("analysis_port", this);
            if (!uvm_config_db #(virtual fusion_axi_vif)::get(this, "", "axi_vif", vif))
                `uvm_fatal("AXI_MON", "Cannot get AXI VIF from config_db")
        endfunction
        
        virtual task run_phase(uvm_phase phase);
            forever begin
                fork
                    begin : WRITE_MONITOR
                        axi_transaction trans;
                        wait_write_transaction();
                        trans = axi_transaction::type_id::create("trans");
                        trans.trans_type = WRITE;
                        trans.addr = vif.awaddr;
                        trans.wdata = vif.wdata;
                        trans.wstrb = vif.wstrb;
                        trans.resp = axi_resp_e'(vif.bresp);
                        analysis_port.write(trans);
                    end
                    begin : READ_MONITOR
                        axi_transaction trans;
                        wait_read_transaction();
                        trans = axi_transaction::type_id::create("trans");
                        trans.trans_type = READ;
                        trans.addr = vif.araddr;
                        trans.rdata = vif.rdata;
                        trans.resp = axi_resp_e'(vif.rresp);
                        analysis_port.write(trans);
                    end
                join_any
                disable fork;
            end
        endtask
        
        virtual task wait_write_transaction();
            @(posedge vif.clk iff (vif.bvalid && vif.bready));
        endtask
        
        virtual task wait_read_transaction();
            @(posedge vif.clk iff (vif.rvalid && vif.rready));
        endtask
    endclass : axi_monitor
    
    // =====================================================================
    // AXI Sequencer
    // =====================================================================
    
    class axi_sequencer extends uvm_sequencer #(axi_transaction);
        `uvm_component_utils(axi_sequencer)
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass : axi_sequencer
    
    // =====================================================================
    // AXI Agent
    // =====================================================================
    
    class axi_agent extends uvm_agent;
        `uvm_component_utils(axi_agent)
        
        axi_driver       driver;
        axi_monitor      monitor;
        axi_sequencer    sequencer;
        
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
        
        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            
            sequencer = axi_sequencer::type_id::create("sequencer", this);
            driver = axi_driver::type_id::create("driver", this);
            monitor = axi_monitor::type_id::create("monitor", this);
        endfunction
        
        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            driver.seq_item_port.connect(sequencer.seq_item_export);
        endfunction
    endclass : axi_agent

endpackage : fusion_axi_pkg
