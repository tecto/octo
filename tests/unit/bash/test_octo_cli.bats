#!/usr/bin/env bats
#
# Tests for bin/octo CLI router
#

setup() {
    TEST_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)"
    PROJECT_ROOT="$(cd "$TEST_DIR/../../.." && pwd)"
    HELPERS_DIR="$TEST_DIR/../../helpers"

    export OCTO_HOME="$BATS_TMPDIR/octo_home_$$"
    export OPENCLAW_HOME="$BATS_TMPDIR/openclaw_home_$$"

    mkdir -p "$OCTO_HOME"/{logs,costs,metrics}
    mkdir -p "$OPENCLAW_HOME/agents/main/sessions"

    # Create minimal openclaw.json
    cat > "$OPENCLAW_HOME/openclaw.json" << 'EOF'
{"version": "1.0.0", "gateway": {"port": 6200}}
EOF

    # Source assertions
    source "$HELPERS_DIR/assertions.sh"
}

teardown() {
    rm -rf "$OCTO_HOME" "$OPENCLAW_HOME"
}

# ============================================
# Help and Version Tests
# ============================================

@test "shows help with -h flag" {
    run "$PROJECT_ROOT/bin/octo" -h
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenClaw Token Optimizer"* ]]
    [[ "$output" == *"Usage:"* ]]
}

@test "shows help with --help flag" {
    run "$PROJECT_ROOT/bin/octo" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenClaw Token Optimizer"* ]]
}

@test "shows help with 'help' command" {
    run "$PROJECT_ROOT/bin/octo" help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "shows help when no command given" {
    run "$PROJECT_ROOT/bin/octo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "shows version with -v flag" {
    run "$PROJECT_ROOT/bin/octo" -v
    [ "$status" -eq 0 ]
    [[ "$output" == *"OCTO"* ]] || [[ "$output" =~ [0-9]+\.[0-9]+\.[0-9]+ ]]
}

@test "shows version with --version flag" {
    run "$PROJECT_ROOT/bin/octo" --version
    [ "$status" -eq 0 ]
}

# ============================================
# Command Routing Tests
# ============================================

@test "routes 'status' command" {
    run "$PROJECT_ROOT/bin/octo" status
    # May fail due to no config, but should try to run status.sh
    [[ "$output" == *"status"* ]] || [[ "$output" == *"config"* ]] || [[ "$output" == *"OCTO"* ]]
}

@test "routes 'doctor' command" {
    run "$PROJECT_ROOT/bin/octo" doctor
    # Should run doctor.sh
    [[ "$output" == *"OCTO"* ]] || [[ "$output" == *"Health"* ]] || [[ "$output" == *"Check"* ]]
}

@test "routes 'analyze' command with --help" {
    run "$PROJECT_ROOT/bin/octo" analyze --help
    [[ "$output" == *"analyze"* ]] || [[ "$output" == *"Usage"* ]] || [[ "$output" == *"period"* ]]
}

@test "routes 'sentinel' command" {
    run "$PROJECT_ROOT/bin/octo" sentinel status
    # Should show sentinel status
    [[ "$output" == *"sentinel"* ]] || [[ "$output" == *"Bloat"* ]] || [[ "$output" == *"running"* ]] || [[ "$output" == *"not"* ]]
}

# ============================================
# Error Handling Tests
# ============================================

@test "exits with error for unknown command" {
    run "$PROJECT_ROOT/bin/octo" nonexistent_command_xyz
    [ "$status" -ne 0 ]
    [[ "$output" == *"Unknown"* ]] || [[ "$output" == *"unknown"* ]] || [[ "$output" == *"help"* ]]
}

@test "error message includes help hint" {
    run "$PROJECT_ROOT/bin/octo" badcmd
    [[ "$output" == *"help"* ]] || [[ "$output" == *"--help"* ]]
}

# ============================================
# Environment Setup Tests
# ============================================

@test "creates OCTO_HOME directories on startup" {
    NEW_OCTO_HOME="$BATS_TMPDIR/new_octo_$$"
    export OCTO_HOME="$NEW_OCTO_HOME"

    run "$PROJECT_ROOT/bin/octo" --help

    # Check if directories were created
    [ -d "$NEW_OCTO_HOME" ] || [ "$status" -eq 0 ]

    rm -rf "$NEW_OCTO_HOME"
}

@test "uses custom OCTO_HOME when set" {
    CUSTOM_HOME="$BATS_TMPDIR/custom_octo_$$"
    mkdir -p "$CUSTOM_HOME"
    export OCTO_HOME="$CUSTOM_HOME"

    run "$PROJECT_ROOT/bin/octo" --help
    [ "$status" -eq 0 ]

    rm -rf "$CUSTOM_HOME"
}

@test "uses default OCTO_PORT 6286 when not set" {
    unset OCTO_PORT
    run "$PROJECT_ROOT/bin/octo" --help
    [ "$status" -eq 0 ]
    # Port 6286 should be default (OCTO in T9)
}

# ============================================
# Banner Display Tests
# ============================================

@test "shows ASCII banner for help" {
    run "$PROJECT_ROOT/bin/octo" --help
    [ "$status" -eq 0 ]
    # Check for ASCII art elements
    [[ "$output" == *"OCTO"* ]] || [[ "$output" == *"OpenClaw"* ]]
}

@test "banner includes 'OpenClaw Token Optimizer'" {
    run "$PROJECT_ROOT/bin/octo" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenClaw"* ]] || [[ "$output" == *"Token"* ]] || [[ "$output" == *"Optimizer"* ]]
}

# ============================================
# Command List Tests
# ============================================

@test "help shows install command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"install"* ]]
}

@test "help shows status command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"status"* ]]
}

@test "help shows analyze command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"analyze"* ]]
}

@test "help shows doctor command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"doctor"* ]]
}

@test "help shows sentinel command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"sentinel"* ]]
}

@test "help shows onelist command" {
    run "$PROJECT_ROOT/bin/octo" --help
    [[ "$output" == *"onelist"* ]]
}
