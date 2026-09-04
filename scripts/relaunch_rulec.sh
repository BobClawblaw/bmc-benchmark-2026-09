#!/bin/bash
# Restart the fixed-binary daemon so the corrected dead-weight rule (7481a8c)
# is the one running for the remainder of the benchmark run.
set -u
BENCH=/mnt/2tbssd/bmc-bench
cd "$BENCH" || exit 2
old=$(cat daemon.pid 2>/dev/null)
kill -TERM "$old" 2>/dev/null
for i in $(seq 1 30); do kill -0 "$old" 2>/dev/null || break; sleep 2; done
kill -9 "$old" 2>/dev/null; sleep 2
mv -f console.log console.rule-c.log 2>/dev/null
setsid nohup nice -n 10 ionice -c3 src/asm/daemon/bitcoind serve "$BENCH/data" > console.log 2>&1 < /dev/null &
echo $! > daemon.pid
date -u +%FT%TZ > epoch.rulec
echo "relaunched with 7481a8c: pid=$(cat daemon.pid)"
