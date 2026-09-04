# bmc vs Bitcoin Core — fresh IBD + serve benchmark (2026-09-04, dedicated SSD)

**Status: bmc download in progress — 77% (743,085 / 965,427 blocks), 11.0 MB/s.**
Live-updated by a 15-minute ticker; the download table below reflects the
state as of the last tick (2026-09-04 14:15 UTC).

Setup: dedicated 1.8 TB SSD (/mnt/2tbssd, ext4), 32-core / 60 GB RAM host,
both nodes syncing from genesis on mainnet. UTXO parity is judged against a
long-synced Bitcoin Core v31.99 oracle on the same box via
`gettxoutsetinfo muhash`. Ports: bmc P2P 8462 / RPC 8461; Core P2P 8563 /
RPC 8562.

## Phase results

| phase | bmc (fix/dlc-peer-floor-depth) | Bitcoin Core v31.1 |
|---|---|---|
| install | git clone 8 s + build 8 s, 0 warnings | download 10 s (87 MB) + sha256 + extract 1 s |
| boot -> P2P listening | ~5 s | queued (starts when bmc's RESULT lands) |
| dns seeds -> peers | +143 in ~1 s | queued |
| headers (416k at that session's tip) | ~129 s (~3.2k hdr/s) | queued |
| block download | **743,085/965,427 (77%), 11.0 MB/s @ 9h48m** | queued |
| disk used (download phase) | 388 GB | queued |
| UTXO build | not yet reached | queued |
| RPC answering | not yet reached (download gate) | queued |
| P2P inbound serving (stranger probe) | not yet reached | queued |
| UTXO-served (gettxoutsetinfo live) | not yet reached | queued |
| muhash parity vs oracle | pending at TIP | pending |
| verdict | RESULT: pending | RESULT: pending |

Download-rate curve observed on bmc: 77 KB/s (regressed binary) -> 4.6 ->
7.2 -> 9.1 -> 11.0 MB/s on the fixed binary as the archive deepens. 33 peer
evictions over the run (Rule C: dead-weight rule, byte floor binding at
every chain depth).

## Headline finding — measured, fixed, re-measured
Commit 93fab72 (2026-09-02) made the dl_catchup byte floor unreachable for
the first ~150k blocks by AND-ing a block-rate exemption into the dead-peer
rule. Result on a fresh install: 22/22 workers under the 32 KB/s floor with
**zero evictions**, 77 KB/s aggregate, ~3-day projected sync. The fix (this
branch's first commit) restores a floor that binds at every chain depth
while keeping both false-positive guards honest — pinned by 7 corners in
test_dialhelper. Same datadir, same peer pool: 77 KB/s -> 7.2 MB/s at
restart, climbing to 11.0 MB/s. See worklog/2026-09-04.md (in the code
repo), analysis/PEER_ANALYSIS.md, logs/floorhunt.log.

## Pipeline (automatic from here)
1. bmc reaches TIP -> phase log stamps RPC / UTXO-served / P2P-serve-ready,
   muhash parity runs vs the oracle, RESULT=PASS/FAIL written.
2. Core v31.1 auto-launches with the identical contract (never overlaps the
   bmc run on this box).
3. This README's table fills in with Core's phases; final consolidated
   report pushed here and in the code repo under
   `benchmarks/2026-09-04-ssd-bmc-vs-core/`.

## Contents
- `scripts/` — install + benchmark + A/B + audit harnesses (all bash/python,
  self-documenting)
- `logs/` — bench.log session log, bmc/core phase & progress, peer
  bisect + floor-hunt measurements, 15-min tick history
- `analysis/` — PEER_ANALYSIS.md (why every peer looked slow), the fix as a
  .patch
- `MEMORY.md` — durable test memory: phases measured vs pending, recovery
  commands, ops notes
