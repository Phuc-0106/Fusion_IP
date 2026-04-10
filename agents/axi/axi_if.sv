// Virtual Interface for Fusion IP UVM Testbench
// This file defines virtual interfaces for AXI4-Lite and Sensor ports

interface fusion_axi_vif(
    input bit clk,
    input bit rst_n
);
    // AXI4-Lite Slave Interface
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;
    
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;
    
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;
    
    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;
    
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;
    
    // Interrupt
    logic        irq;

endinterface : fusion_axi_vif



