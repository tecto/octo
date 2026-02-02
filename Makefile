# OCTO - OpenClaw Token Optimizer
# Makefile for testing and development

.PHONY: all test test-unit test-integration test-e2e test-bash test-python test-typescript lint clean help

# Default target
all: test

# ============================================
# Test Targets
# ============================================

# Run all tests
test: test-unit test-integration

# Run unit tests only
test-unit: test-bash test-python test-typescript

# Run bash unit tests
test-bash:
	@echo "Running Bash unit tests..."
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/unit/bash/; \
	else \
		echo "bats not installed. Install with: npm install -g bats"; \
		exit 1; \
	fi

# Run Python unit tests
test-python:
	@echo "Running Python unit tests..."
	@if command -v pytest >/dev/null 2>&1; then \
		pytest tests/unit/python/ -v; \
	else \
		echo "pytest not installed. Install with: pip install pytest pytest-mock"; \
		exit 1; \
	fi

# Run TypeScript unit tests
test-typescript:
	@echo "Running TypeScript unit tests..."
	@if command -v jest >/dev/null 2>&1; then \
		jest tests/unit/typescript/ --passWithNoTests; \
	else \
		echo "jest not installed. Install with: npm install -g jest ts-jest @types/jest"; \
	fi

# Run integration tests
test-integration:
	@echo "Running integration tests..."
	@chmod +x tests/helpers/*.sh
	@./tests/helpers/setup_test_env.sh
	@if command -v bats >/dev/null 2>&1; then \
		bats tests/integration/*.bats; \
	fi
	@if command -v pytest >/dev/null 2>&1; then \
		pytest tests/integration/*.py -v; \
	fi

# Run E2E tests
test-e2e:
	@echo "Running E2E tests..."
	@chmod +x tests/e2e/*.sh
	@./tests/e2e/test_full_install.sh
	@./tests/e2e/test_bloat_recovery.sh

# Run E2E tests with Docker (requires Docker)
test-e2e-docker:
	@echo "Running E2E tests with Docker..."
	@chmod +x tests/e2e/*.sh
	@./tests/e2e/test_onelist_docker.sh

# Run tests with coverage
test-coverage:
	@echo "Running tests with coverage..."
	@pytest tests/unit/python/ --cov=lib/core --cov-report=html --cov-report=term

# ============================================
# Lint Targets
# ============================================

# Run all linters
lint: lint-bash lint-python

# Lint bash scripts
lint-bash:
	@echo "Linting Bash scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck bin/octo lib/cli/*.sh lib/watchdog/*.sh 2>/dev/null || true; \
	else \
		echo "shellcheck not installed"; \
	fi

# Lint Python code
lint-python:
	@echo "Linting Python code..."
	@if command -v flake8 >/dev/null 2>&1; then \
		flake8 lib/core/*.py --max-line-length=120 || true; \
	fi
	@if command -v black >/dev/null 2>&1; then \
		black --check lib/core/*.py || true; \
	fi

# Format Python code
format-python:
	@echo "Formatting Python code..."
	@if command -v black >/dev/null 2>&1; then \
		black lib/core/*.py; \
	else \
		echo "black not installed. Install with: pip install black"; \
	fi

# ============================================
# Development Targets
# ============================================

# Install development dependencies
dev-setup:
	@echo "Installing development dependencies..."
	@pip install pytest pytest-mock pytest-cov flake8 black
	@npm install -g bats jest ts-jest @types/jest typescript

# Setup test environment
setup-test-env:
	@chmod +x tests/helpers/*.sh
	@./tests/helpers/setup_test_env.sh

# Teardown test environment
teardown-test-env:
	@chmod +x tests/helpers/*.sh
	@./tests/helpers/teardown_test_env.sh

# ============================================
# Clean Targets
# ============================================

# Clean test artifacts
clean:
	@echo "Cleaning test artifacts..."
	@rm -rf tests/tmp
	@rm -rf .pytest_cache
	@rm -rf __pycache__
	@rm -rf lib/core/__pycache__
	@rm -rf htmlcov
	@rm -f coverage.xml
	@rm -f .coverage
	@find . -name "*.pyc" -delete
	@find . -name "__pycache__" -type d -delete

# ============================================
# Help
# ============================================

help:
	@echo "OCTO Test Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Test Targets:"
	@echo "  test              Run all tests (unit + integration)"
	@echo "  test-unit         Run unit tests only"
	@echo "  test-bash         Run Bash unit tests"
	@echo "  test-python       Run Python unit tests"
	@echo "  test-typescript   Run TypeScript unit tests"
	@echo "  test-integration  Run integration tests"
	@echo "  test-e2e          Run E2E tests"
	@echo "  test-e2e-docker   Run E2E tests with Docker"
	@echo "  test-coverage     Run tests with coverage report"
	@echo ""
	@echo "Lint Targets:"
	@echo "  lint              Run all linters"
	@echo "  lint-bash         Lint Bash scripts"
	@echo "  lint-python       Lint Python code"
	@echo "  format-python     Format Python code with black"
	@echo ""
	@echo "Development Targets:"
	@echo "  dev-setup         Install development dependencies"
	@echo "  setup-test-env    Setup test environment"
	@echo "  teardown-test-env Teardown test environment"
	@echo ""
	@echo "Clean Targets:"
	@echo "  clean             Clean test artifacts"
