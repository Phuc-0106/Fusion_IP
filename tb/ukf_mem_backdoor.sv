// =============================================================
// ukf_mem_backdoor.sv — hierarchical peek into DUT state RAM
//
// Questa wraps this file in package ukf_mem_backdoor_sv_unit (see vlog
// banner). fusion_scoreboard_pkg does: import ukf_mem_backdoor_sv_unit::*;
// User-defined packages must not use $root here (vlog-7053); the auto
// *_sv_unit package is accepted for $root in peek_word().
//
// Requires top tb_fusion_ip, instance dut (fusion_ip_top), u_mem.mem[].
// =============================================================
`include "params.vh"

class ukf_state_mem_backdoor;
    static function logic [31:0] peek_word(int unsigned addr);
`ifdef SIMULATION
        return $root.tb_fusion_ip.dut.u_mem.mem[addr[7:0]];
`else
        return '0;
`endif
    endfunction

    static task automatic poke_word(int unsigned addr, logic [31:0] w);
`ifdef SIMULATION
        $root.tb_fusion_ip.dut.u_mem.mem[addr[7:0]] = w;
`endif
    endtask
endclass

// AXI MMIO shadow (fusion_ip_top) — for DT alignment checks (+UKF_DEBUG_DT)
class fusion_reg_backdoor;
    static function logic [31:0] peek_reg_dt();
`ifdef SIMULATION
        return $root.tb_fusion_ip.dut.reg_dt;
`else
        return '0;
`endif
    endfunction
endclass
