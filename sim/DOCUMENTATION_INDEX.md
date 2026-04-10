# Fusion IP UVM Documentation Index

Complete index of all documentation files for the Fusion IP UVM verification environment.

## 📚 Main Documentation Files

### Getting Started

| File | Purpose | Reading Time |
|------|---------|--------------|
| [QUICK_START.md](QUICK_START.md) | 5-minute quick start guide | 5 min |
| [README.md](README.md) | Project overview and structure | 10 min |
| [INSTALLATION.md](INSTALLATION.md) | Linux environment setup | 15 min |

### Building & Running Tests

| File | Purpose | Reading Time |
|------|---------|--------------|
| [BUILD_GUIDE.md](BUILD_GUIDE.md) | Complete build workflow | 20 min |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common problems & solutions | 25 min |
| [BEST_PRACTICES.md](BEST_PRACTICES.md) | Development guidelines | 30 min |

### UVM Framework (in `uvm/` directory)

| File | Purpose |
|------|---------|
| `uvm/base/fusion_pkg.sv` | Core types, enums, transactions |
| `uvm/base/fusion_ral.sv` | Register Abstraction Layer (RAL) |
| `uvm/agents/axi/axi_agent.sv` | AXI4-Lite driver/monitor/sequencer |
| `uvm/agents/sensor/sensor_agent.sv` | Sensor data driver/monitor/sequencer |
| `uvm/environment/fusion_env.sv` | Environment, base test, global sequences |
| `uvm/environment/fusion_scoreboard.sv` | Scoreboard and prediction logic |
| `uvm/ref_model/ukf_predictor.sv` | UKF reference model |
| `uvm/tests/fusion_tests.sv` | All test cases (T1-T8) |
| `uvm/fusion_tb_top.sv` | Top-level testbench module |

---

## 🚀 Quick Navigation

### I want to... 

#### Get Started (New User)

1. **First time setup?**
   - Read: [QUICK_START.md](QUICK_START.md) (5 min)
   - Then: [INSTALLATION.md](INSTALLATION.md) (15 min)
   - Command: `bash sim/setup.sh`

2. **Run first test?**
   - Read: [QUICK_START.md](QUICK_START.md) - "First Test" section
   - Command: `cd sim && source ./project_env.bash && make test-sanity`

3. **Understand the system?**
   - Read: [README.md](README.md) - Architecture section
   - Then: [BUILD_GUIDE.md](BUILD_GUIDE.md) - Workflow Overview

#### Build & Test

4. **Build the project**
   - Read: [BUILD_GUIDE.md](BUILD_GUIDE.md) - "Compilation" section
   - Command: `make clean && make build`

5. **Run tests**
   - Single test: `make test-sanity`
   - Multiple tests: `perl regress.pl`
   - See [BUILD_GUIDE.md](BUILD_GUIDE.md) - "Run Single Test"

6. **Analyze results**
   - Check logs: `cat log/run.log`
   - View waveforms: `make wave`
   - See [BUILD_GUIDE.md](BUILD_GUIDE.md) - "Analyze Results"

#### Debug Issues

7. **Something is broken?**
   - Read: [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
   - Find your error type (Environment/Compilation/Simulation/Regression/Tool)
   - Follow suggested solution

8. **Need performance tips?**
   - Read: [BUILD_GUIDE.md](BUILD_GUIDE.md) - "Performance Tips"
   - Or: [BEST_PRACTICES.md](BEST_PRACTICES.md) - "Performance Optimization"

#### Develop Tests

9. **Write a new test?**
   - Read: [BEST_PRACTICES.md](BEST_PRACTICES.md) - "Test Development"
   - Template: See "Test Template Structure" section
   - Add to [regress.cfg](regress.cfg)

10. **Add new testbench component?**
    - Read: [BEST_PRACTICES.md](BEST_PRACTICES.md) - "Code Organization"
    - See: [README.md](README.md) - Architecture section
    - Follow file structure under `uvm/`

#### Maintain Project

11. **Run regression?**
    - Read: [BUILD_GUIDE.md](BUILD_GUIDE.md) - "Regression Testing"
    - Command: `perl regress.pl -j 4`

12. **Keep code clean?**
    - Read: [BEST_PRACTICES.md](BEST_PRACTICES.md) - "Maintenance"
    - Check: [.gitignore](.gitignore) for proper version control

---

## 📂 File Organization

```
d:\Fusion_IP\
├── README.md                               # Main project description
├── .gitignore                              # Git ignore patterns
│
├── sim/
│   ├── QUICK_START.md                      # 5-minute tutorial
│   ├── INSTALLATION.md                     # Setup on Linux
│   ├── README.md                           # Build guide overview
│   ├── BUILD_GUIDE.md                      # Detailed build workflow
│   ├── TROUBLESHOOTING.md                  # Problem solutions
│   ├── BEST_PRACTICES.md                   # Development guidelines
│   │
│   ├── project_env.bash                    # Environment setup
│   ├── compile.f                           # Master compile list
│   ├── rtl.f                               # RTL sources
│   ├── tb.f                                # Testbench sources
│   │
│   ├── Makefile                            # Build automation
│   ├── regress.cfg                         # Test configuration
│   ├── regress.pl                          # Regression runner
│   │
│   ├── setup.sh                            # Initial setup
│   ├── run.sh                              # Quick test runner
│   ├── clean.sh                            # Cleanup utility
│   ├── modelsim.ini                        # Questa config
│
├── uvm/
│   ├── base/
│   │   ├── fusion_pkg.sv                   # Core definitions
│   │   └── fusion_ral.sv                   # Register model
│   │
│   ├── agents/
│   │   ├── axi/
│   │   │   └── axi_agent.sv                # AXI VIP
│   │   │
│   │   └── sensor/
│   │       └── sensor_agent.sv             # Sensor VIP
│   │
│   ├── environment/
│   │   ├── fusion_env.sv                   # UVM environment
│   │   └── fusion_scoreboard.sv            # Scoreboard
│   │
│   ├── ref_model/
│   │   └── ukf_predictor.sv                # Reference model
│   │
│   ├── tests/
│   │   └── fusion_tests.sv                 # Test cases
│   │
│   └── fusion_tb_top.sv                    # Testbench top
│
├── docs/
│   └── UVM_TESTBENCH.md                    # Original specification
│
└── [RTL files - cordic.sv, fp_sqrt.sv, etc.]
```

---

## 🔍 How to Use This Index

### Method 1: By Task

If you know what you want to do:
1. Go to section "I want to..." above
2. Find your task
3. Click the link to the relevant documentation

### Method 2: By File Type

If you know which file to look at:
1. Go to section "📂 File Organization"
2. Find the file
3. Read the associated documentation

### Method 3: By Problem Type

If you have an error:
1. Go to [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
2. Find your error category
3. Follow the suggested solution

---

## 📖 Documentation Detail Levels

### Level 1: Quick (5-15 minutes)
- Best for: Getting started, quick questions
- Read: [QUICK_START.md](QUICK_START.md)
- Also: First part of [BUILD_GUIDE.md](BUILD_GUIDE.md)

### Level 2: Intermediate (15-30 minutes)
- Best for: Running tests, understanding workflow
- Read: [README.md](README.md), [INSTALLATION.md](INSTALLATION.md)
- Also: [BUILD_GUIDE.md](BUILD_GUIDE.md)

### Level 3: Advanced (30-60 minutes)
- Best for: Development, troubleshooting, extending
- Read: [BEST_PRACTICES.md](BEST_PRACTICES.md), [TROUBLESHOOTING.md](TROUBLESHOOTING.md)
- Also: Source code comments in `uvm/` directory

### Level 4: Expert (1-2 hours)
- Best for: Deep understanding, system design
- Read: All of above + source code
- Also: Original [docs/UVM_TESTBENCH.md](../docs/UVM_TESTBENCH.md) specification

---

## 🔗 Cross-References

### Environment Setup Path
```
QUICK_START → INSTALLATION → BUILD_GUIDE (Setup section)
```

### Build & Test Path
```
QUICK_START → BUILD_GUIDE (Compilation & Run sections)
```

### Debugging Path
```
TROUBLESHOOTING → BUILD_GUIDE (Analyze Results) → BEST_PRACTICES (Debugging)
```

### Development Path
```
BEST_PRACTICES (Test Development) → Source Code (uvm/) → QUICK_START (Integration)
```

---

## 📋 Documentation Checklist

For quick reference, here's what's covered where:

| Topic | Where | Reference |
|-------|-------|-----------|
| Linux setup | INSTALLATION.md | Section 1 |
| First test | QUICK_START.md | Section 2 |
| Build workflow | BUILD_GUIDE.md | Section 1 |
| Compilation | BUILD_GUIDE.md | Section 2 |
| Running tests | BUILD_GUIDE.md | Section 3 |
| Regression | BUILD_GUIDE.md | Section 5 |
| Waveforms | BUILD_GUIDE.md | Section 6 |
| Environment errors | TROUBLESHOOTING.md | Section 1 |
| Compile errors | TROUBLESHOOTING.md | Section 2 |
| Runtime errors | TROUBLESHOOTING.md | Section 3 |
| Regression issues | TROUBLESHOOTING.md | Section 4 |
| Tool issues | TROUBLESHOOTING.md | Section 5 |
| Test development | BEST_PRACTICES.md | Section 1 |
| Code organization | BEST_PRACTICES.md | Section 2 |
| Debugging | BEST_PRACTICES.md | Section 3 |
| Performance | BEST_PRACTICES.md | Section 4 |
| Maintenance | BEST_PRACTICES.md | Section 5 |
| CI/CD | BEST_PRACTICES.md | Section 7 |

---

## 🆘 FAQ - Frequently Asked Questions

**Q: Where do I start?**
A: Read [QUICK_START.md](QUICK_START.md) first (5 min), then run the commands.

**Q: How do I install this on my Linux machine?**
A: Follow [INSTALLATION.md](INSTALLATION.md) step by step.

**Q: What if something breaks?**
A: Check [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for your error type.

**Q: How do I write a new test?**
A: Read [BEST_PRACTICES.md](BEST_PRACTICES.md) Section 1: "Test Development Best Practices"

**Q: How do I optimize simulation speed?**
A: See [BEST_PRACTICES.md](BEST_PRACTICES.md) Section 4: "Performance Optimization Tips"

**Q: Where can I find my test logs?**
A: Check `sim/log/` directory, or run `cat log/run.log`

**Q: How do I run multiple tests at once?**
A: Use `perl regress.pl`, see [BUILD_GUIDE.md](BUILD_GUIDE.md) Section 5.

**Q: Can I use a different simulator (VCS, Xcelium)?**
A: Yes! See Makefile SIMULATOR variable, [BUILD_GUIDE.md](BUILD_GUIDE.md) covers this.

---

## 🔄 Document Maintenance

**Last Updated:** 2024-04-02
**Version:** 1.0

When updating documentation:
1. Update this index with any new files
2. Maintain cross-references
3. Keep "Last Updated" date current
4. Review quarterly for accuracy

---

## 📞 Support Resources

### Internal
- Source code comments: `uvm/*.sv`
- Configuration examples: `regress.cfg`, `modelsim.ini`
- Previous test runs: `log/` directory

### External
- UVM Specification: `$UVM_HOME/docs/`  
- Questa Help: `vsim -h`, `vlog -h`
- Linux Documentation: `man make`, `man bash`, `man perl`

---

**Navigation Guide Complete!** 🗺️  
Start with [QUICK_START.md](QUICK_START.md) and follow the links as needed.

