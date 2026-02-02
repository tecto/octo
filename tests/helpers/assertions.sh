#!/usr/bin/env bash
#
# Custom assertions for OCTO bats tests
#

# Assert that a file exists
assert_file_exists() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "Expected file to exist: $file" >&2
        return 1
    fi
}

# Assert that a directory exists
assert_dir_exists() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        echo "Expected directory to exist: $dir" >&2
        return 1
    fi
}

# Assert that output contains a string
assert_output_contains() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: $expected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# Assert that output does not contain a string
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output NOT to contain: $unexpected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# Assert that a JSON file contains a key with a value
assert_json_value() {
    local file="$1"
    local key="$2"
    local expected="$3"
    local actual
    actual=$(jq -r "$key" "$file" 2>/dev/null)
    if [[ "$actual" != "$expected" ]]; then
        echo "Expected $key to be '$expected', got '$actual'" >&2
        return 1
    fi
}

# Assert that a process is running
assert_process_running() {
    local pattern="$1"
    if ! pgrep -f "$pattern" > /dev/null; then
        echo "Expected process matching '$pattern' to be running" >&2
        return 1
    fi
}

# Assert that a process is not running
assert_process_not_running() {
    local pattern="$1"
    if pgrep -f "$pattern" > /dev/null; then
        echo "Expected process matching '$pattern' NOT to be running" >&2
        return 1
    fi
}

# Assert that a port is listening
assert_port_listening() {
    local port="$1"
    if ! (lsof -i ":$port" 2>/dev/null || ss -tln 2>/dev/null | grep -q ":$port "); then
        echo "Expected port $port to be listening" >&2
        return 1
    fi
}

# Assert exit code
assert_exit_code() {
    local expected="$1"
    if [[ "$status" -ne "$expected" ]]; then
        echo "Expected exit code $expected, got $status" >&2
        return 1
    fi
}
