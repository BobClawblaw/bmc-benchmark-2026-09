#!/bin/bash
# Verify the final dead-weight rule (rule C) against the pinned corners, then
# rebuild, amend the commit, push, relaunch the fixed daemon.
set -eu
cd /mnt/2tbssd/bmc-bench/src

# test corners must match the final semantics:
#   low bytes -> dead (any block count); healthy bytes+blocks -> alive;
#   healthy bytes + <10 blocks but 2x floor bytes -> alive; marginal bytes +
#   stalled blocks -> dead; no reading -> alive.
python3 - <<'EOF'
p='asm/tests/test_dialhelper.c'
s=open(p).read()
old = '''      ok(dlc_dead_weight(2000.0, 0), "2 KB/s and no blocks this tick: dead weight");
      ok(dlc_dead_weight(2000.0, 9), "2 KB/s and 9 blocks: still dead weight (below the block floor)");
      ok(dlc_dead_weight(2000.0, 50), "2 KB/s and 50 blocks: dead weight too (byte floor binds at any depth)");
      ok(!dlc_dead_weight(50000.0, 50), "50 KB/s and 50 blocks: pulling its weight, not banned");
      ok(!dlc_dead_weight(1500000.0, 1), "1.5 MB/s and one block: fine near the tip");'''
new = '''      ok(dlc_dead_weight(2000.0, 0), "2 KB/s and no blocks this tick: dead weight");
      ok(dlc_dead_weight(2000.0, 9), "2 KB/s and 9 blocks: still dead weight (byte floor binds at any depth)");
      ok(dlc_dead_weight(2000.0, 50), "2 KB/s and 50 blocks: dead weight too (a block rate can launder bytes)");
      ok(!dlc_dead_weight(50000.0, 50), "50 KB/s and 50 blocks: pulling its weight, not banned");
      ok(!dlc_dead_weight(1500000.0, 1), "1.5 MB/s and one block: fine near the tip");
      ok(dlc_dead_weight(40000.0, 1), "40 KB/s and one block: marginal bytes AND stalled blocks");
      ok(!dlc_dead_weight(200000.0, 1), "200 KB/s and one block: big blocks, not stalled");'''
assert old in s, "test corners anchor not found"
open(p,'w').write(s.replace(old,new,1))
print("test corners updated")
EOF

cd asm
make -s tests/test_dialhelper 2>&1 | head -3
./tests/test_dialhelper 2>&1 | grep -E "dead weight|marginal|big blocks|fine near|pulling|TESTS"
make -j"$(nproc)" -s daemon/bitcoind daemon/bitcoin_cli
cd ..
git add -A
git commit -q --amend -m "download workers: the byte floor binds at every chain depth

93fab72 fixed the fresh-install false positives (the 32KB/s byte floor banned
honest peers serving tiny early blocks) by AND-ing a block-rate check into
the dead-weight rule: a peer keeping >=10 blocks/tick was exempt from the
byte floor. That exemption is exactly the hole that stalled every fresh
install in the early chain -- on the 2026-09-04 run on /mnt/2tbssd, 22 of 22
workers sat under 32KB/s with zero evictions for 20+ minutes, 77KB/s
aggregate, ~3 days projected. The block-rate exemption only ever made sense
early-chain, where 10 tiny blocks really are few bytes; but the same 10
blocks/s is 12MB/s near the tip, where the exemption is meaningless because
the byte floor binds anyway. Measured on a real 30k-block hole with one
datadir and one peer pool: byte floor only 1.4MB/s, AND-rule 77KB/s (0
kills), block-floor variants 2.0MB/s.

The rule is now: under the byte floor is dead at any depth (a 6-block/s peer
trickling 12KB/s is a slow peer wherever it lives in the chain); at or above
the floor, a peer is only dead if its block rate is ALSO stalled AND its
bytes are within 2x of the floor (40KB/s with one block/tick is a peer that
has stopped making progress; 1.5MB/s with one block/tick is just a big
block). test_dialhelper pins all seven corners.

Co-Authored-By: Hermes Agent <hermes@nousresearch.com>"
git log --oneline -1
git push -f -q origin fix/dlc-peer-floor-depth 2>&1 | tail -1
echo NEW_COMMIT=$(git rev-parse HEAD)
