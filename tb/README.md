# TB - Testbench

This directory contains the top-level testbench and UVM environment for verifying Fusion IP.

## Contents

- **tb_fusion_ip.sv** - Top-level testbench module
- **fusion_env.sv** - UVM environment definition
- **fusion_base_test.sv** - Base test class for all tests
- Supporting environment files

## Structure

```
tb/
├── tb_fusion_ip.sv          # Top-level wrapper for DUT + agents
├── fusion_env.sv            # UVM environment (agents, scoreboards)
├── fusion_base_test.sv      # Base test class
├── compile.f                # TB-specific filelist
└── README.md                # This file
```

## Key Components

### fusion_env
- Instantiates all UVM agents
- Configures agent behavior
- Sets up virtual interfaces
- Manages scoreboards and reference models

### tb_fusion_ip
- Instantiates DUT (fusion_ip_top)
- Connects testbench agents to DUT
- Routes clocks/resets to all components

### fusion_base_test
- Base class for all test cases
- Common TLM port connections
- Default factory overrides
- Recovery mechanisms

## Running Tests

```bash
cd sim
make test-sanity           # Run sanity test
make test-multi            # Run multi-cycle test
make test-all              # Run all tests
```

## Adding New Tests

1. Create test class in testcases/ inheriting from fusion_base_test
2. Add test-xxx target to sim/Makefile
3. Add entry to regress.cfg for regression
4. Run: `make test-xxx`

## Environment Configuration

Pass plusargs to configure test:

```bash
make run TESTNAME=fusion_sanity_test +UVM_VERBOSITY=UVM_HIGH
```

## Notes

- All testbenches follow UVM 1.2 standard
- Virtual interfaces defined in DPI layer (see uvm/base/)
- Coverage collection ready (use COV=ON in make)

