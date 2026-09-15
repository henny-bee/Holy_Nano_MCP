# Holy Nano MCP
#
# Requires the holyc-lang compiler (hcc) on a Linux/macOS host.
# On Windows, run these targets inside WSL2 - see docs/PHASE0.md.

BIN      := build/holy-nano-mcp
SRC      := $(shell find src -name '*.HC')
TESTS    := test_json test_mcp test_auth test_provider
TEST_BINS := $(addprefix build/,$(TESTS))

.PHONY: all build test unit integration clean status toolchain help

all: build

build: $(BIN)

$(BIN): $(SRC)
	@mkdir -p build generated
	hcc src/main.HC -o $(BIN)
	@echo "built: $(BIN)"

build/test_%: tests/test_%.HC $(SRC) tests/harness.HC
	@mkdir -p build
	hcc $< -o $@

unit: $(TEST_BINS)
	@for t in $(TEST_BINS); do $$t || exit 1; done

integration: build
	bash scripts/run-tests.sh

test: integration

status: build
	$(BIN) --status

toolchain:
	bash scripts/install-toolchain.sh

clean:
	rm -rf build
	rm -f generated/*.png generated/*.jpg generated/*.webp

help:
	@echo "make build        compile the server to $(BIN)"
	@echo "make unit         compile and run the HolyC unit tests"
	@echo "make test         full suite, including the mock-API integration tests"
	@echo "make status       print resolved provider, model and credential source"
	@echo "make toolchain    install the holyc-lang compiler"
	@echo "make clean        remove build output and generated images"
