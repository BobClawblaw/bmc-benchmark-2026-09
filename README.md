# bmc vs Bitcoin Core — fresh IBD + serve benchmark (2026-09-04, dedicated SSD)

**Status: bmc UTXO catch-up 94% — block download GATE PASSED. Core queued.**
Last update 2026-09-05 03:41 UTC, from live logs. The phase table below is
the measured record; the serve-phase gates land within the hour.

Setup: dedicated 1.8 TB SSD (/mnt/2tbssd, ext4), 32-core / 60 GB RAM host,
both nodes from genesis on mainnet, UTXO parity judged against a long-synced
Bitcoin Core v31.99 oracle (`gettxoutsetinfo muhash`). Ports: bmc P2P 8462 /
RPC 8461; Core P2P 8563 / RPC 8562.

## Phase results so far

| phase | measured | timestamp (UTC) |
|---|---|---|
| install (bmc) | clone 8 s + build 8 s, 0 warnings | 02:40 |
| boot -> P2P inbound listening | ~5 s (served peers throughout the entire sync) | 04:23 |
| dns seeds -> 143 candidate peers | +1 s | 04:23 |
| headers 416k | ~129 s (~3.2k hdr/s) | 04:25 |
| **block download (GATE 1)** | **719,257 blocks in 70,211 s (~19.5 h), 11.1 MB/s sustained flat**, ~1 TB archive | done 23:53:35 |
| **RPC bound + cookie (GATE 2)** | 8461 live, .cookie 0600, within 0.5 s of the download gate closing | 23:53:35 |
| P2P inbound accepts | 101 accepted during sync (serve children fork+answer) | continuous |
| **UTXO bulk catch-up (GATE 3)** | 906,356 / 965,539 (93.9%), avg 67 blk/s, mid-catchup background compaction (14 runs -> 1 in 58 s), ~30 GB RSS peak | running |
| coinstats adopted (GATE 4) | pending (ETA <15 min) | — |
| TIP + muhash parity vs oracle (GATE 5) | pending | — |
| verdict | RESULT: pending | — |
| Bitcoin Core v31.1 full run | queued — auto-launches at bmc RESULT, same contract, never overlapping | — |

Notes on the download gate: 11.1 MB/s was flat across the entire span
(early tiny-block chain and the fat modern span) — the binding constraint
after the peer-floor fix was link/peer quality, not disk (0.4 GiB/s SSD) or
CPU. The pre-fix binary on the identical datadir/pool: 77 KB/s with 22/22
workers stuck under the eviction floor and zero evictions — a ~140x
difference. See analysis/PEER_ANALYSIS.md, logs/floorhunt.log, and the
worklog entry in the code repo.

## Headline finding — measured, fixed, re-measured
93fab72 (2026-09-02) made the dl_catchup byte floor unreachable for the
first ~150k blocks via a block-rate exemption AND-joined into the dead-peer
rule; fresh installs could not evict anything. The shipped fix (this
repo's first commit, `download workers: the byte floor binds at every chain
depth`) restores a depth-honest floor pinned by 7 test corners. Follow-up
work (EMA speed-ranked peer selection) is implemented and test-green, held
locally pending upstream merge.

## Pipeline (automatic from here)
1. GATE 3 completes (~03:55 UTC) -> GATE 4 coinstats -> GATE 5 TIP + muhash
   parity -> RESULT.
2. Core v31.1 auto-launches (fresh datadir, same phase contract).
3. Final consolidated report (all gates, both nodes, parity verdicts)
   replaces the tables above; the code-repo copy under
   `benchmarks/2026-09-04-ssd-bmc-vs-core/` refreshes from the same logs.

## Contents
- `scripts/` — install + benchmark + A/B + audit harnesses
- `logs/` — session log, phase/progress logs, bisect + floor-hunt data,
  15-min tick history (ticks carry the full rate history)
- `analysis/` — PEER_ANALYSIS.md (root-cause audit), PEER_PLAN.md (EMA
  selection design, implemented), ASSUMEUTXO_PLAN.md, the fix as .patch
- `PERF_PLAN.md` — ranked program vs Core with live status
- `MEMORY.md` — durable test memory + recovery commands
