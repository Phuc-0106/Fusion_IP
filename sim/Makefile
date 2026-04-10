# Makefile for Fusion IP UVM Testbench (Linux/Unix optimized)
# Supports Questa/ModelSim, VCS, Xcelium
# Usage: make [target] [OPTION=value]

# =====================================================================
# Configuration Variables (override on command line)
# =====================================================================

# Simulator choice
SIMULATOR ?= questa
# Tool path (usually in PATH already)
TOOL_BIN ?=

# RTL and TB
RTL_FILE = rtl.f
TB_FILE = tb.f
COMPILE_FILE = compile.f

# Testbench configuration
TB_NAME ?= tb_fusion_ip
WORK_LIB ?= work
TESTNAME ?= fusion_sanity_test
VERBOSITY ?= UVM_MEDIUM
SEED ?= 1
RUNARG ?=
# Questa: appended to vsim (e.g. +UKF_DEBUG_P for covariance debug in fusion_scoreboard)
EXTRA_VSIM_OPTS ?=

# Directories
WORK_DIR = work
LOG_DIR = log
BUILD_DIR = build
WAVE_DIR = waves

# Coverage
COV ?= OFF
COV_DIR = coverage

# Diagnostic options
UVM_RELATED_WARNINGS ?= NO
DEBUG_MODE ?= OFF
# With DUMP_WAVES=1: pass -novopt unless DUMP_WAVES_NOVOPT=0 (faster sim, may reduce WLF/context)
DUMP_WAVES_NOVOPT ?=
# Arithmetic: always IEEE-754 float32 (USE_FP32 is defined unconditionally in params.vh)

# =====================================================================
# Derived Variables
# =====================================================================

# Create timestamp for log naming
TIMESTAMP = $(shell date +%Y%m%d_%H%M%S)

# Log file naming
LOG_FILE = $(LOG_DIR)/$(TESTNAME)_$(SEED)_$(TIMESTAMP).log
RUN_LOG = $(LOG_DIR)/run.log

# Waveform file
WAVE_FILE = $(WAVE_DIR)/$(TESTNAME)_$(SEED).wlf
WAVE_FSDB = $(WAVE_DIR)/$(TESTNAME)_$(SEED).fsdb

# Coverage database
COVERAGE_DB = $(COV_DIR)/$(TESTNAME)_$(SEED).ucdb

# =====================================================================
# Tool-Specific Options
# =====================================================================

ifeq ($(SIMULATOR),questa)
VLOG = vlog
VSIM = vsim
VLIB = vlib
VMAP = vmap
# Open saved WLF: Intel Questa FSE often has no qwave in PATH (use vsim GUI, cf. ref Makefile).
# Include DUT explicitly — WLF only contains logged regions; full TB path pulls in fusion_ip_top dut.
# Override: make wave WAVE_VIEW_CMD='qwave $(WAVE_FILE) &'
WAVE_VIEW_CMD ?= $(VSIM) -i -view $(WAVE_FILE) -do "add wave -r vsim:/$(TB_NAME)/dut/*;"

	# Compilation flags (USE_FP32 always active via params.vh — no flag needed)
	ifeq ($(DEBUG_MODE),ON)
		VLOG_OPTS = -sv +define+SIMULATION +define+DEBUG_MODE
	else
		VLOG_OPTS = -sv +define+SIMULATION
	endif
	
	# Coverage compilation (if enabled)
	ifeq ($(COV),ON)
		VLOG_OPTS += -cover sbcdefx
	endif

	# Wave dump: Questa 2024+ deprecates vlog +acc=rmb (vlog-14401). Use vsim -voptargs=+acc only.
	
	# Simulation flags — use exactly ONE -do script. A second -do can run
	# "run -all; quit" before "log -r ...", so no WLF is written to $(WAVE_FILE).
	# cd into TB then log -r /* recursively; plain "log -r sim:/tb" can miss objects / empty WLF context.
	ifeq ($(DUMP_WAVES),1)
		QUESTA_VSIM_DO = cd sim:/$(TB_NAME); log -r /*; run -all; quit
	else
		QUESTA_VSIM_DO = run -all; quit
	endif
	VSIM_OPTS = -c -do "$(QUESTA_VSIM_DO)" -suppress 12110
	VSIM_OPTS += +UVM_TESTNAME=$(TESTNAME)
	VSIM_OPTS += +UVM_VERBOSITY=$(VERBOSITY)
	# e.g. EXTRA_VSIM_OPTS=+UKF_DEBUG_P (P/Q/R/dt dump in scoreboard)
	VSIM_OPTS += $(EXTRA_VSIM_OPTS)
	ifeq ($(DUMP_WAVES),1)
		VSIM_OPTS += -wlf $(WAVE_FILE)
		VSIM_OPTS += -voptargs=+acc
		# Disable vopt so log/WLF keep full object context (override: DUMP_WAVES_NOVOPT=0)
		ifneq ($(DUMP_WAVES_NOVOPT),0)
			VSIM_OPTS += -novopt
		endif
	endif
	
	# Coverage flags
	ifeq ($(COV),ON)
		VSIM_OPTS += -coverage -covfile $(COVERAGE_DB)
	endif
	
	# Debug hooks
	ifeq ($(DEBUG_MODE),ON)
		VSIM_OPTS += -debugdb
	endif
endif

ifeq ($(SIMULATOR),vcs)
VLOG = vcs
VCS_OPTS = -sverilog -timescale=1ns/1ps +define+SIMULATION -cm line+cond+fsm
# USE_FP32 is unconditional — no flag needed

	ifeq ($(DEBUG_MODE),ON)
		VCS_OPTS += -debug_all
	endif

RUN_OPTS = +UVM_TESTNAME=$(TESTNAME) +UVM_VERBOSITY=$(VERBOSITY)

	ifeq ($(DUMP_WAVES),1)
		VCS_OPTS += -fsdb
		RUN_OPTS += +fsdb+autoflush
	endif
endif

ifeq ($(SIMULATOR),xcelium)
XMVLOG = xmvlog
XMSIM = xmsim
XMVLOG_OPTS = -sv +define+SIMULATION
XMSIM_OPTS = -input run.do

	ifeq ($(DUMP_WAVES),1)
		XMSIM_OPTS += -fsdb
	endif
endif

# =====================================================================
# Targets
# =====================================================================

.PHONY: all build elaborate run clean help wave wave-run cov_gui cov_merge test-\
	sanity multi missing-gps irq reset ral sb csv regress

# Default target
all: build run

# =====================================================================
# Build Targets (Questa/ModelSim)
# =====================================================================

ifeq ($(SIMULATOR),questa)

build: $(WORK_DIR)
	@echo "[BUILD] Compiling with $(SIMULATOR)..."
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	$(VLIB) $(WORK_DIR)
	$(VMAP) work $(WORK_DIR)
	@echo "[VLOG] Compiling RTL and TB sources from $(COMPILE_FILE)..."
	$(VLOG) $(VLOG_OPTS) -f $(COMPILE_FILE)
	@echo "[BUILD] Compilation successful"

elaborate: build
	@echo "[ELAB] Elaboration not separate step for Questa (implicit in vlog)"

run: build
	@echo "[RUN] Starting simulation: $(TESTNAME) with SEED=$(SEED)"
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	$(VSIM) $(VSIM_OPTS) $(TB_NAME) \
		-sv_seed $(SEED) \
		$(RUNARG) \
		-logfile $(LOG_FILE) 2>&1 | tee -a $(LOG_FILE)
	@ln -sf $(LOG_FILE) $(RUN_LOG)
	@echo "[RUN] Simulation complete - log: $(LOG_FILE)"
	@echo "[RUN] Summary:"
	@tail -20 $(LOG_FILE)

endif

# =====================================================================
# Build Targets (VCS)
# =====================================================================

ifeq ($(SIMULATOR),vcs)

build: $(WORK_DIR)
	@echo "[BUILD] Compiling with $(SIMULATOR)..."
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	$(VLOG) $(VCS_OPTS) -f $(COMPILE_FILE) -output $(WORK_DIR)/simv
	@echo "[BUILD] Compilation successful"

elaborate: build
	@echo "[ELAB] Elaboration implicit in VCS compile"

run: build
	@echo "[RUN] Starting simulation: $(TESTNAME)"
	@mkdir -p $(LOG_DIR)
	cd $(WORK_DIR) && ./simv $(RUN_OPTS) +seed=$(SEED) $(RUNARG) | tee -a ../$(LOG_FILE)
	@ln -sf $(LOG_FILE) $(RUN_LOG)

endif

# =====================================================================
# Build Targets (Xcelium)
# =====================================================================

ifeq ($(SIMULATOR),xcelium)

build: $(WORK_DIR)
	@echo "[BUILD] Compiling with $(SIMULATOR)..."
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	$(XMVLOG) $(XMVLOG_OPTS) -f $(COMPILE_FILE)
	@echo "[BUILD] Compilation successful"

elaborate: build
	@echo "[ELAB] Elaborating with $(SIMULATOR)..."
	xmelab -f $(COMPILE_FILE) -top $(TB_NAME)

run: elaborate
	@echo "[RUN] Simulation: $(TESTNAME)"
	@mkdir -p $(LOG_DIR)
	echo "run" > run.do
	$(XMSIM) $(XMSIM_OPTS) $(TB_NAME) \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(VERBOSITY) \
		+seed=$(SEED) $(RUNARG) \
		| tee -a $(LOG_FILE)
	@ln -sf $(LOG_FILE) $(RUN_LOG)

endif

# =====================================================================
# Waveform and Coverage Targets
# =====================================================================

# Do not list $(WAVE_FILE) as a prerequisite — there is no rule that creates it.
# .wlf is only written when you run with DUMP_WAVES=1 (single -do must run log before run).
wave:
	@if [ ! -f $(WAVE_FILE) ]; then \
		echo "[WAVE] ERROR: $(WAVE_FILE) not found."; \
		echo "       One-shot sim + waves + GUI:"; \
		echo "         make wave-run TESTNAME=$(TESTNAME) SEED=$(SEED)"; \
		echo "       Or only generate the .wlf:"; \
		echo "         make run DUMP_WAVES=1 TESTNAME=$(TESTNAME) SEED=$(SEED)"; \
		echo "         make debug-wave   # default test + DUMP_WAVES + verbose"; \
		exit 1; \
	fi
	@echo "[WAVE] Opening waveform: $(WAVE_FILE)"
	$(WAVE_VIEW_CMD) &

# Run simulation with wave dump, then open Questa viewer (same TESTNAME/SEED as wave).
wave-run:
	@echo "[WAVE-RUN] Simulating with DUMP_WAVES=1 -> $(WAVE_FILE)"
	@$(MAKE) run DUMP_WAVES=1 TESTNAME=$(TESTNAME) SEED=$(SEED) RUNARG="$(RUNARG)"
	@if [ ! -f $(WAVE_FILE) ]; then \
		echo "[WAVE-RUN] ERROR: $(WAVE_FILE) still missing after run (check vsim log)."; \
		exit 1; \
	fi
	@echo "[WAVE-RUN] Opening $(WAVE_FILE)"
	$(WAVE_VIEW_CMD) &

cov_gui: $(COVERAGE_DB)
	@echo "[COV] Opening coverage GUI for: $(COVERAGE_DB)"
	$(VSIM) -i -viewcov $(COVERAGE_DB) &

cov_merge:
	@echo "[COV] Merging coverage databases..."
	qcover -datafile merged.ucdb \
		$(shell find $(COV_DIR) -name '*.ucdb' -type f)
	qcover -datafile merged.ucdb

# =====================================================================
# Convenient Test Shortcuts
# =====================================================================

test-sanity:
	$(MAKE) run TESTNAME=fusion_sanity_test

test-multi:
	$(MAKE) run TESTNAME=fusion_multi_cycle_test

test-missing-gps:
	$(MAKE) run TESTNAME=fusion_missing_gps_test

test-irq:
	$(MAKE) run TESTNAME=fusion_irq_status_test

test-reset:
	$(MAKE) run TESTNAME=fusion_soft_reset_test

test-ral:
	$(MAKE) run TESTNAME=fusion_ral_bit_bash_test

test-sb:
	$(MAKE) run TESTNAME=fusion_scoreboard_ref_test

# T8 reads tb/golden/golden_stimulus.csv (from scripts/generate_golden.py), not fused_timeline.csv
# RUNARG must be VAR=value; a bare +PLUSARG is parsed by sub-make as an extra goal.
test-csv:
	$(MAKE) run TESTNAME=fusion_csv_route_test RUNARG="$(RUNARG)"

# Note: FP32 is the only arithmetic mode.
# Old test-fp32-* targets removed — test-sanity/multi/csv already run FP32.

# Run all tests sequentially
test-all: test-sanity test-multi test-missing-gps test-irq \
	test-reset test-ral test-sb test-csv
	@echo "[TEST-ALL] All tests completed!"

# =====================================================================
# LDLᵀ Regression — exercises sigma_point_generator after the
# LL→LDL refactoring.  No extra testbench needed: the existing UVM
# infrastructure compares DUT outputs against the SV predictor
# (ukf_predictor.sv, also updated to LDLᵀ).
#
# Targets are identical to test-sanity / test-multi / test-csv but
# are grouped here for clarity and easy CI invocation:
#   make test-ldl-sanity    — 1 UKF cycle, all sensors valid
#   make test-ldl-multi     — 5 UKF cycles with drifting GPS
#   make test-ldl-csv       — AIS golden-data CSV route (full sequence)
#   make test-ldl           — all three in sequence
#   make test-ldl-fp32      — same three in FP32 mode
# =====================================================================

test-ldl-sanity:
	@echo "[LDL] T1 sanity — LDLᵀ sigma path"
	$(MAKE) run TESTNAME=fusion_sanity_test

test-ldl-multi:
	@echo "[LDL] T2 multi-cycle — LDLᵀ sigma path"
	$(MAKE) run TESTNAME=fusion_multi_cycle_test

test-ldl-csv:
	@echo "[LDL] T8 CSV route — LDLᵀ sigma path"
	$(MAKE) run TESTNAME=fusion_csv_route_test RUNARG="$(RUNARG)"

# Primary regression for LDLᵀ: sanity + multi-cycle + CSV in order
test-ldl: test-ldl-sanity test-ldl-multi test-ldl-csv
	@echo "[LDL] LDLᵀ regression complete"

# Note: USE_FP32 is always active — test-ldl-fp32 is now identical to test-ldl.
test-ldl-fp32: test-ldl

# =====================================================================
# Utility Targets
# =====================================================================

$(WORK_DIR):
	@mkdir -p $(WORK_DIR)

clean:
	@echo "[CLEAN] Removing build artifacts..."
	@rm -rf $(WORK_DIR) *.wlf *.shm *.fsdb transcript modelsim.ini $(WAVE_DIR) $(BUILD_DIR)
	@rm -rf work_* xsim_* *.o *.so *.lib *.a
	@echo "[CLEAN] Complete"

clean-logs:
	@echo "[CLEAN] Removing log files..."
	@rm -rf $(LOG_DIR)
	@echo "[CLEAN-LOG] Complete"

clean-all: clean clean-logs
	@echo "[CLEAN-ALL] Everything cleaned"

# =====================================================================
# Batch/Regression Support
# =====================================================================

regress:
	@echo "[REGRESS] Starting regression from regress.cfg..."
	perl regress.pl

regress-report:
	@echo "[REGRESS] Generating report from existing logs..."
	perl regress.pl -r

# Useful pattern: run single test with verbose output
debug:
	$(MAKE) run VERBOSITY=UVM_HIGH DEBUG_MODE=ON SEED=1

# Run with waveform capture
debug-wave:
	$(MAKE) run DUMP_WAVES=1 VERBOSITY=UVM_HIGH DEBUG_MODE=ON

# Run with coverage
coverage:
	$(MAKE) run COV=ON TESTNAME=fusion_sanity_test

# =====================================================================
# Information Targets
# =====================================================================

info:
	@echo "========== Fusion IP UVM Build Info =========="
	@echo "Simulator:        $(SIMULATOR)"
	@echo "Testbench:        $(TB_NAME)"
	@echo "Default Test:     $(TESTNAME)"
	@echo "Work Directory:   $(WORK_DIR)"
	@echo "Log Directory:    $(LOG_DIR)"
	@echo "Wave Directory:   $(WAVE_DIR)"
	@echo "Python Version:   $$(perl --version 2>/dev/null | head -1)"
	@echo "=========================================="

help:
	@echo ""
	@echo "Fusion IP UVM Testbench - Makefile Targets"
	@echo ""
	@echo "Main Targets:"
	@echo "  all               Build and run default test ($(TESTNAME))"
	@echo "  build             Compile RTL and TB only"
	@echo "  elaborate         Elaborate design (VCS/Xcelium only)"
	@echo "  run               Run simulation (requires build)"
	@echo "  clean             Remove all build artifacts"
	@echo "  clean-logs        Remove log files only"
	@echo ""
	@echo "Test Shortcuts:"
	@echo "  test-sanity       T1 - Sanity test (1 cycle)"
	@echo "  test-multi        T2 - Multi-cycle test"
	@echo "  test-missing-gps  T3 - Missing GPS test"
	@echo "  test-irq          T4 - Interrupt test"
	@echo "  test-reset        T5 - Soft reset test"
	@echo "  test-ral          T6 - RAL bit bash test"
	@echo "  test-sb           T7 - Scoreboard reference test"
	@echo "  test-csv          T8 - CSV route test"
	@echo "  test-all          Run all tests (T1-T8)"
	@echo ""
	@echo "LDLᵀ Regression (sigma_point_generator LDL refactor):"
	@echo "  test-ldl-sanity   LDLᵀ T1 - sanity (1 cycle)"
	@echo "  test-ldl-multi    LDLᵀ T2 - multi-cycle (5 cycles)"
	@echo "  test-ldl-csv      LDLᵀ T8 - CSV AIS route"
	@echo "  test-ldl          LDLᵀ regression: sanity + multi + csv"
	@echo "  test-ldl-fp32     LDLᵀ regression compiled with USE_FP32"
	@echo ""
	@echo "Debug/Analysis Targets:"
	@echo "  debug             Run with high verbosity and debug info"
	@echo "  debug-wave        Run with debug + waveform dump"
	@echo "  wave              Open WLF with vsim -view (see wave-run)"
	@echo "  wave-run          Run sim with DUMP_WAVES=1 then open viewer (same TESTNAME/SEED)"
	@echo "  coverage          Run with coverage enabled"
	@echo "  cov_gui           Open coverage database GUI"
	@echo "  cov_merge         Merge all coverage databases"
	@echo ""
	@echo "Regression:"
	@echo "  regress           Run full regression (reads regress.cfg)"
	@echo "  regress-report    Generate report from existing logs"
	@echo ""
	@echo "Info:"
	@echo "  info              Show build configuration"
	@echo "  help              Show this help message"
	@echo ""
	@echo "Options (pass on command line):"
	@echo "  SIMULATOR=<sim>   Simulator: questa | vcs | xcelium [default: questa]"
	@echo "  TESTNAME=<name>   Test class name [default: $(TESTNAME)]"
	@echo "  SEED=<num>        Random seed [default: 1]"
	@echo "  VERBOSITY=<lvl>   UVM_HIGH | UVM_MEDIUM | UVM_LOW [default: $(VERBOSITY)]"
	@echo "  DUMP_WAVES=1      Enable waveform dumping"
	@echo "  DUMP_WAVES_NOVOPT=0  With DUMP_WAVES=1, skip vsim -novopt (faster; WLF may lack context)"
	@echo "  WORK_LIB=<lib>    Library for tb top (default: work) — used by wave viewer"
	@echo "  (FP32 is always IEEE-754; no flag needed — defined in params.vh)"
	@echo "  DEBUG_MODE=ON     Enable debug mode"
	@echo "  COV=ON            Enable coverage"
	@echo "  RUNARG='args'     Additional plusargs"
	@echo ""
	@echo "Examples:"
	@echo "  make test-sanity"
	@echo "  make run TESTNAME=fusion_multi_cycle_test SEED=42"
	@echo "  make debug TESTNAME=fusion_irq_status_test"
	@echo "  make coverage TESTNAME=fusion_sanity_test"
	@echo "  make SIMULATOR=vcs test-all"
	@echo "  make test-all VERBOSITY=UVM_HIGH DUMP_WAVES=1"
	@echo "  make wave-run TESTNAME=fusion_csv_route_test SEED=1"
	@echo ""

# =====================================================================
# Default
# =====================================================================

.DEFAULT_GOAL := help

