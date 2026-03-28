#!/bin/bash
# benchmark_write_cliff.sh
# Disk I/O stress test to reproduce the write cliff and thundering herd effect on vSAN/consumer SSDs.
# Usage: Run as root or with sufficient permissions. Use with caution on production systems.

set -e

TEST_FILE="/tmp/benchmark_write_cliff.testfile"
BLOCK_SIZE=4K
TOTAL_SIZE=2G
RUNTIME=300 # seconds

# Write test: sustained random writes
fio --name=write_cliff_test \
    --filename=$TEST_FILE \
    --size=$TOTAL_SIZE \
    --bs=$BLOCK_SIZE \
    --rw=randwrite \
    --ioengine=libaio \
    --direct=1 \
    --numjobs=4 \
    --runtime=$RUNTIME \
    --time_based \
    --group_reporting

# Read test: sustained random reads
fio --name=read_cliff_test \
    --filename=$TEST_FILE \
    --size=$TOTAL_SIZE \
    --bs=$BLOCK_SIZE \
    --rw=randread \
    --ioengine=libaio \
    --direct=1 \
    --numjobs=4 \
    --runtime=$RUNTIME \
    --time_based \
    --group_reporting

rm -f $TEST_FILE
