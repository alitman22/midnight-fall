#!/bin/bash
# benchmark_write_cliff.sh
# Disk I/O stress test to reproduce the write cliff and thundering herd effect on vSAN/consumer SSDs.
# Usage: Run as root or with sufficient permissions. Use with caution on production systems.

set -e

TEST_FILE="/tmp/benchmark_write_cliff.testfile"
BLOCK_SIZE="4K"
TOTAL_SIZE="2G"
RUNTIME=300
JOBS=4

usage() {
    cat <<'EOF'
Usage:
  benchmark_write_cliff.sh [options]

Options:
  --duration SEC      Runtime in seconds for each test phase (default: 300)
  --block-size SIZE   FIO block size, e.g. 4k, 16k (default: 4K)
  --total-size SIZE   Test file size, e.g. 2G, 8G (default: 2G)
  --jobs N            Parallel jobs (default: 4)
  --file PATH         Test file path (default: /tmp/benchmark_write_cliff.testfile)
  -h, --help          Show this help

Notes:
  Designed/tested for Ubuntu 20.04 environments.
EOF
}

require_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: required command not found: $1" >&2
        exit 1
    fi
}

is_positive_int() {
    [[ "$1" =~ ^[1-9][0-9]*$ ]]
}

while [ $# -gt 0 ]; do
    case "$1" in
        --duration)
            RUNTIME="${2:-}"
            shift 2
            ;;
        --block-size)
            BLOCK_SIZE="${2:-}"
            shift 2
            ;;
        --total-size)
            TOTAL_SIZE="${2:-}"
            shift 2
            ;;
        --jobs)
            JOBS="${2:-}"
            shift 2
            ;;
        --file)
            TEST_FILE="${2:-}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "ERROR: unknown argument '$1'" >&2
            usage
            exit 1
            ;;
    esac
done

if ! is_positive_int "$RUNTIME" || ! is_positive_int "$JOBS"; then
    echo "ERROR: --duration and --jobs must be positive integers." >&2
    exit 1
fi

require_cmd fio

cleanup() {
    rm -f "$TEST_FILE"
}

trap cleanup EXIT

echo "Running write-cliff benchmark: duration=${RUNTIME}s bs=${BLOCK_SIZE} size=${TOTAL_SIZE} jobs=${JOBS} file=${TEST_FILE}"

# Write test: sustained random writes
fio --name=write_cliff_test \
    --filename="$TEST_FILE" \
    --size="$TOTAL_SIZE" \
    --bs="$BLOCK_SIZE" \
    --rw=randwrite \
    --ioengine=libaio \
    --direct=1 \
    --numjobs="$JOBS" \
    --runtime="$RUNTIME" \
    --time_based \
    --group_reporting

# Read test: sustained random reads
fio --name=read_cliff_test \
    --filename="$TEST_FILE" \
    --size="$TOTAL_SIZE" \
    --bs="$BLOCK_SIZE" \
    --rw=randread \
    --ioengine=libaio \
    --direct=1 \
    --numjobs="$JOBS" \
    --runtime="$RUNTIME" \
    --time_based \
    --group_reporting
