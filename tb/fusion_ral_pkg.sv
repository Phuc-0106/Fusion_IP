// =====================================================================
// Fusion IP RAL (Register Abstraction Layer) Package
// =====================================================================

package fusion_ral_pkg;
    import uvm_pkg::*;
    import fusion_pkg::*;
    `include "uvm_macros.svh"
    
    // =====================================================================
    // Register Block Definition Stub
    // =====================================================================
    
    class fusion_reg_block extends uvm_reg_block;
        `uvm_object_utils(fusion_reg_block)
        
        // Registers will be defined here
        
        function new(string name = "fusion_reg_block");
            super.new(name);
        endfunction
        
        virtual function void build();
            default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN);
        endfunction
    endclass : fusion_reg_block
    
    // =====================================================================
    // Adapter for register accesses (RAL ↔ AXI)
    // =====================================================================
    
    class fusion_reg2axi_adapter extends uvm_reg_adapter;
        `uvm_object_utils(fusion_reg2axi_adapter)
        
        function new(string name = "fusion_reg2axi_adapter");
            super.new(name);
            // Enable automatic mapping of address and data
            supports_byte_enable = 1;
            provides_responses = 1;
        endfunction
        
        // Convert register operation → AXI transaction
        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            axi_transaction axi_xn;
            
            axi_xn = axi_transaction::type_id::create("axi_xn");
            
            // Convert register operation to AXI command
            if (rw.kind == UVM_READ) begin
                axi_xn.trans_type = READ;
            end else begin
                axi_xn.trans_type = WRITE;
            end
            
            // Map register address to AXI address
            axi_xn.addr = rw.addr;
            
            // For write operations, copy data
            if (rw.kind == UVM_WRITE) begin
                axi_xn.wdata = rw.data;
                axi_xn.wstrb = 4'hF;  // Full write strobe (all bytes enabled)
            end else begin
                axi_xn.wstrb = 4'h0;  // No write for read operations
            end
            
            return axi_xn;
        endfunction
        
        // Convert AXI transaction → register operation response
        virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
            axi_transaction axi_xn;
            
            if (!$cast(axi_xn, bus_item)) begin
                `uvm_fatal("CAST_ERROR", "Failed to cast bus_item to axi_transaction")
            end
            
            // For read operations, extract data from read response
            if (rw.kind == UVM_READ) begin
                rw.data = axi_xn.rdata;
            end
            
            // Map AXI response to UVM status
            case (axi_xn.resp)
                OKAY:   rw.status = UVM_IS_OK;
                SLVERR: rw.status = UVM_NOT_OK;
                DECERR: rw.status = UVM_NOT_OK;
                default: rw.status = UVM_IS_OK;
            endcase
        endfunction
    endclass : fusion_reg2axi_adapter
    
endpackage : fusion_ral_pkg
