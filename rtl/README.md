# RTL - Design Files

This directory contains all RTL (Register Transfer Level) source files for the Fusion IP design.

## Contents

- **params.vh** - Global parameters and constants used across all modules
- **\*.sv** - SystemVerilog RTL modules

## Modules

| Module | Purpose |
|--------|---------|
| fusion_ip_top.sv | Top-level design wrapper |
| ukf_controller.sv | UKF state machine controller |
| predict_block.sv | EKF prediction block |
| update_block.sv | EKF update block |
| sensor_input_block.sv | Sensor data conditioning |
| sigma_point_generator.sv | Sigma point generation |
| matrix_math_core.sv | Matrix computation engine |
| state_mem_reg.sv | State register file |
| cordic.sv | CORDIC-based trigonometric functions |
| fp_sqrt.sv | Fixed-point square root |
| sync_fifo.sv | Synchronous FIFO buffer |

## Compilation

```bash
cd sim
vlog -sv +define+SIMULATION -f ../rtl/compile.f
```

Or as part of full build:
```bash
make build
```

## Adding New Modules

1. Add SystemVerilog file to rtl/
2. Update rtl/compile.f
3. Update sim/Makefile if new parameters needed
4. Run `make clean && make build`

## Notes

- All modules follow Fusion IP coding standards
- Include params.vh for global constants
- Synthesis tested with Xilinx Vivado
- Place & Route validated for target FPGA

