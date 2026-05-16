# =============================================================================
# Makefile - SV-only starter scaffold for the SPI Master Verification Project
# -----------------------------------------------------------------------------
# This is a concrete Makefile derived from harness/Makefile.template. It is
# pre-wired for the SV-only scaffold that lives next to it (no UVM) and can
# be consumed directly by the grader without modification.
# =============================================================================

SIMULATOR ?= model
SEED      ?= 0
TEST      ?= sanity_test
WAVES     ?= 0

# Force recursive make to use a shell-safe command (avoid "C:/Program Files (x86)/.../make")
MAKE := make

# Resolve the project root from this file's location.
# harness/examples/sv_only/Makefile  -> ../../..
# changed project root from ../../.. to . since we moved the Makefile from harness/examples/sv_only/ to Project Implementation/
PROJ_ROOT  ?= .
HARNESS    ?= $(PROJ_ROOT)/harness
STUDENT_TB ?= $(PROJ_ROOT)/tb

# DUT sources (three-file golden RTL). The grader overrides DUT_SRCS to
# point at faulty_rtl/*_buggy.sv when it injects a bug.
DUT_SRCS   ?= \
  $(PROJ_ROOT)/golden_rtl/spi_core.sv \
  $(PROJ_ROOT)/golden_rtl/apb_regfile.sv \
  $(PROJ_ROOT)/golden_rtl/spi_master.sv
DUT_SRC    ?=
EFF_DUT_SRCS = $(if $(strip $(DUT_SRC)),$(DUT_SRC),$(DUT_SRCS))

# ---- student source lists ---------------------------------------------------
TB_SRCS    ?= \
  $(STUDENT_TB)/apb_master_bfm.sv \
  $(STUDENT_TB)/spi_slave_bfm.sv \
  $(STUDENT_TB)/tb_top.sv

ENV_SRCS   ?= \
  $(PROJ_ROOT)/env/ref_model.sv \
  $(PROJ_ROOT)/env/coverage.sv

SEQ_SRCS   ?= \
  $(PROJ_ROOT)/sequences/stim_lib.sv

ASSERT_SRCS?= \
  $(PROJ_ROOT)/assertions/spi_sva.sv


INC_DIRS   ?= +incdir+$(HARNESS) +incdir+$(PROJ_ROOT)/env +incdir+$(STUDENT_TB) +incdir+$(PROJ_ROOT)/sequences +incdir+$(PROJ_ROOT)/assertions

# ---- regression list --------------------------------------------------------
REGRESSION_TESTS = \
  sanity_test \
  reg_access_test \
  mode_coverage_test \
  width_coverage_test \
  fifo_stress_test \
  interrupt_test \
  clk_div_corner_test \
  loopback_test \
  delay_transfer_test \
  error_injection_test \
  randomized_sanity_test
 
REGRESSION_SEEDS ?= 1   # 10 * 20 = 200 runs (well under the 10000 cap)

# ============================================================================
# Questa flow (default)
# ============================================================================
ifeq ($(SIMULATOR),model)

VLOG_FLAGS  = -sv -timescale=1ns/1ps +acc=rn +define+SIM $(INC_DIRS)
COV_FLAG    = +cover

compile:
	@mkdir -p build
	vlib work
	vlog $(VLOG_FLAGS) $(COV_FLAG) \
	   $(HARNESS)/apb_if.sv \
	   $(HARNESS)/spi_if.sv \
	   $(EFF_DUT_SRCS) \
	   $(HARNESS)/dut_wrapper.sv \
	   $(ENV_SRCS) \
	   $(SEQ_SRCS) \
	   $(ASSERT_SRCS) \
	   $(TB_SRCS)

run: compile
	vsim -c -coverage work.tb_top \
	     +TESTNAME=$(TEST) +UVM_TESTNAME=$(TEST) +SEED=$(SEED) \
	     -do "coverage save -onexit cov_$(TEST)_$(SEED).ucdb; run -all; quit -f"


define REGRESS_ONE
	echo "=== Running $(1) for $(REGRESSION_SEEDS) seeds ===" ; \
	for s in `seq 1 $(REGRESSION_SEEDS)` ; do \
		echo "[INFO] $(1) seed=$$s" ; \
	    $(MAKE) -s run TEST=$(1) SEED=$$s WAVES=0 \
	      > build/log_$(1)_$$s.log 2>&1 ; \
	done ; \
	:
endef

regress: compile
	@mkdir -p build
	@$(foreach t,$(REGRESSION_TESTS),$(call REGRESS_ONE,$(t)) ;)
	vcover merge -out build/merged.ucdb *.ucdb

cov:
	@if [ -f build/merged.ucdb ]; then \
	    vcover report -details build/merged.ucdb > coverage_report.txt ; \
	    echo "Coverage report: coverage_report.txt" ; \
	else \
	    echo "No merged.ucdb - run 'make regress' first" ; exit 1 ; \
	fi

clean:
	rm -rf work build *.wlf *.vstf *.ucdb transcript coverage_report.txt

endif

.PHONY: compile run run_bonus regress cov clean