# MDIO PHY Combined Model Simulation Makefile
# SystemVerilog 2012, Icarus Verilog
# SPDX-License-Identifier: Apache-2.0

# Tool Configuration
IVERILOG      = iverilog
IVERILOG_FLAGS = -Wtimescale -g2012
VVP           = vvp
VVP_FLAGS     = -n
GTKWAVE       = gtkwave
GTKWAVE_FLAGS = 
DOXYGEN       = doxygen
PULSEVIEW     = pulseview
VCD2CSV       = ./tools/vcd_to_pulseview_csv.py


# Project Structure
PROJNAME           = mdio_phy_combined_model
DIR_SIMULATION     = iverilog/simulation
DIR_TESTBENCH      = iverilog/testbench
DIR_SOURCE         = .
DIR_LIB           = ../lib
DIR_DOC           = docgen

# File Paths
IVL_FILE          = $(DIR_SIMULATION)/$(PROJNAME).ivl
VCD_FILE          = $(DIR_SIMULATION)/$(PROJNAME).vcd
CSV_FILE          = $(DIR_SIMULATION)/$(PROJNAME).csv
WAVE_CONFIG       = $(wildcard $(DIR_TESTBENCH)/*.gtkw)
DOXYFILE          = Doxyfile

# Source Files
SOURCES           = $(wildcard $(DIR_SOURCE)/*.sv)
TESTBENCH_SOURCES = $(wildcard $(DIR_TESTBENCH)/*.sv)
LIB_SOURCES       = $(wildcard $(DIR_LIB)/*.sv)
ALL_SOURCES       = $(SOURCES) $(TESTBENCH_SOURCES) $(LIB_SOURCES)
ALL_DOC_SOURCES   = $(SOURCES) $(TESTBENCH_SOURCES)

# Default target
.DEFAULT_GOAL := help

# --------------------------------------------------------------------
# Simulation Targets
# --------------------------------------------------------------------

# Main simulation target
all: simulation pulse-data

# Create necessary directories
directories:
	@mkdir -p $(DIR_SIMULATION) $(DIR_DOC)

# Compile the design
compile: directories
	@echo "Compiling sources..."
	@echo "  Sources: $(SOURCES)"
	@echo "  Testbenches: $(TESTBENCH_SOURCES)"
	@echo "  Libraries: $(LIB_SOURCES)"
	$(IVERILOG) $(IVERILOG_FLAGS) -o $(IVL_FILE) $(ALL_SOURCES)
	@echo "Compilation completed: $(IVL_FILE)"

# Run simulation
run: $(IVL_FILE)
	@echo "Running simulation..."
	@rm -f $(VCD_FILE)
	$(VVP) $(VVP_FLAGS) $(IVL_FILE)
	@if [ -f *.vcd ]; then \
		mv *.vcd $(VCD_FILE); \
		echo "VCD file generated: $(VCD_FILE)"; \
	else \
		echo "Error: No VCD file generated"; \
		exit 1; \
	fi
	@echo "Simulation completed successfully"

# Complete simulation (compile + run)
simulation: compile run

# View waveforms
wave: $(VCD_FILE)
	@echo "Launching GTKWave..."
	@if [ -n "$(WAVE_CONFIG)" ]; then \
		$(GTKWAVE) $(GTKWAVE_FLAGS) $(VCD_FILE) $(WAVE_CONFIG) & \
	else \
		$(GTKWAVE) $(GTKWAVE_FLAGS) $(VCD_FILE) & \
	fi

# Quick simulation and view (combined target)
quick: simulation wave

# --------------------------------------------------------------------
# Documentation Targets
# --------------------------------------------------------------------

# Generate Doxygen configuration file
doxyfile: directories
	@echo "Generating Doxygen configuration..."
	@cp -f Doxyfile.template $(DOXYFILE) 2>/dev/null || \
	( echo "Doxyfile.template not found, creating default Doxyfile..." && \
	  $(DOXYGEN) -g $(DOXYFILE) > /dev/null 2>&1 && \
	  echo "Please configure $(DOXYFILE) manually and run 'make docs' again" )

docs/mdio_fsm_auto.dot: mdio_phy_combined_model.sv tools/gen_mdio_fsm.py
	python3 tools/gen_mdio_fsm.py mdio_phy_combined_model.sv > $@

# Generate documentation
docs: docs/mdio_fsm_auto.dot doxyfile
	@echo "Generating documentation..."
	@if [ -f "$(DOXYFILE)" ]; then \
		$(DOXYGEN) $(DOXYFILE); \
		echo "Documentation generated in $(DIR_DOC)/html/"; \
		echo "Open $(DIR_DOC)/html/index.html in your browser"; \
	else \
		echo "Error: Doxyfile not found. Run 'make doxyfile' first."; \
		exit 1; \
	fi

# View documentation (open in default browser)
view-docs: docs
	@echo "Opening documentation in browser..."
	@if command -v xdg-open > /dev/null; then \
		xdg-open $(DIR_DOC)/html/index.html; \
	elif command -v open > /dev/null; then \
		open $(DIR_DOC)/html/index.html; \
	else \
		echo "Please open $(DIR_DOC)/html/index.html manually"; \
	fi

# Clean documentation
clean-docs:
	@echo "Cleaning documentation..."
	@rm -rf $(DIR_DOC)/html $(DIR_DOC)/latex
	@rm -f $(DOXYFILE)
	@if [ -d "$(DIR_DOC)" ] && [ -z "$$(ls -A $(DIR_DOC))" ]; then \
		rmdir $(DIR_DOC); \
		echo "Documentation directory removed"; \
	else \
		echo "Documentation cleaned (directory kept as it contains other files)"; \
	fi

# Force clean documentation (removes entire doc directory)
clean-docs-force:
	@echo "Force cleaning documentation..."
	@rm -rf $(DIR_DOC)
	@rm -f $(DOXYFILE)
	@echo "Documentation directory completely removed"

pulse-data:
	@$(VCD2CSV) "$(VCD_FILE)" "$(CSV_FILE)" --gtkw "$(WAVE_CONFIG)" --ignore-missing
	@echo "csv generated"

pulse-view: pulse-data
	$(PULSEVIEW) "$(CSV_FILE)" &

# --------------------------------------------------------------------
# Analysis and Debugging Targets
# --------------------------------------------------------------------

# Run with verbose output
verbose: IVERILOG_FLAGS += -V
verbose: VVP_FLAGS += -v
verbose: simulation

# Generate lint report
lint: directories
	@echo "Running lint checks..."
	$(IVERILOG) -t null $(IVERILOG_FLAGS) $(ALL_SOURCES)

# Check syntax only
syntax:
	@echo "Checking syntax..."
	$(IVERILOG) -t null $(IVERILOG_FLAGS) $(ALL_SOURCES)
	@echo "Syntax check passed"

# Generate dependency information
deps:
	@echo "Source dependencies:"
	@echo "  Design sources: $(SOURCES)"
	@echo "  Testbench sources: $(TESTBENCH_SOURCES)"
	@echo "  Library sources: $(LIB_SOURCES)"
	@echo "  Documentation sources: $(words $(ALL_DOC_SOURCES)) files"

# --------------------------------------------------------------------
# Utility Targets
# --------------------------------------------------------------------

# Clean all generated files
clean: clean-docs
	@echo "Cleaning simulation files..."
	@rm -rf $(DIR_SIMULATION)
	@rm -f *.vcd *.ivl *.log
	@echo "Clean completed"

# Clean simulation only (keep docs)
clean-sim:
	@echo "Cleaning simulation files only..."
	@rm -rf $(DIR_SIMULATION)
	@rm -f *.vcd *.ivl *.log
	@echo "Simulation files cleaned"

# Display help information
help:
	@echo "MDIO PHY Combined Model Simulation Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  all          - Run complete simulation (default)"
	@echo "  simulation   - Compile and run simulation"
	@echo "  compile      - Compile sources only"
	@echo "  run          - Run simulation only (requires compilation)"
	@echo "  wave         - View waveforms in GTKWave"
	@echo "  quick        - Run simulation and immediately view waveforms"
	@echo "  docs         - Generate Doxygen documentation"
	@echo "  view-docs    - Generate and view documentation in browser"
	@echo "  doxyfile     - Generate Doxygen configuration file"
	@echo "  clean-docs   - Remove generated documentation"
	@echo "  clean-sim    - Remove simulation files only (keep docs)"
	@echo "  verbose      - Run simulation with verbose output"
	@echo "  lint         - Run lint checks on sources"
	@echo "  syntax       - Check syntax only"
	@echo "  deps         - Show source dependencies"
	@echo "  clean        - Remove all generated files"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Project: $(PROJNAME)"
	@echo "Sources: $(words $(ALL_SOURCES)) files"
	@echo "Documentation: $(words $(ALL_DOC_SOURCES)) files"

# Display current configuration
config:
	@echo "Current Configuration:"
	@echo "  Project: $(PROJNAME)"
	@echo "  Simulation dir: $(DIR_SIMULATION)"
	@echo "  Testbench dir: $(DIR_TESTBENCH)"
	@echo "  Source dir: $(DIR_SOURCE)"
	@echo "  Library dir: $(DIR_LIB)"
	@echo "  Documentation dir: $(DIR_DOC)"
	@echo "  IVERILOG: $(IVERILOG) $(IVERILOG_FLAGS)"
	@echo "  VVP: $(VVP) $(VVP_FLAGS)"
	@echo "  DOXYGEN: $(DOXYGEN)"

# --------------------------------------------------------------------
# Phony Targets Declaration
# --------------------------------------------------------------------
.PHONY: all simulation directories compile run wave quick \
        verbose lint syntax deps clean clean-sim clean-docs help config \
        docs view-docs doxyfile clean-docs-force pulse-view pulse-data
