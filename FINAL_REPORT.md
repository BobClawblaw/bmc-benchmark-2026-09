# FINAL REPORT — bmc vs Bitcoin Core: fresh-install IBD + serve benchmark
**Dedicated SSD (/mnt/2tbssd, ext4), 32-core / 60 GB RAM, 2026-09-04 → 2026-09-06 UTC**

## Headline
**Three-way UTXO parity: PASS.** bmc's chainstate == Core v31.1's == the
long-synced Core v31.99 oracle's — identical muhash, txouts, bogosize,
bestblock at height 965,702 (`b5dd0933…e518e6fc` / 165,329,921 txouts).
Two strict-rule checks during the run (965,565 and final 965,702): both
PASS. bmc built its set independently (custom LSM, its own assembly
consensus, full-script-verification replay from genesis).

## Timings
| phase | bmc | Core v31.1 |
|---|---|---|
| install | 16 s (clone+build, 0 warn) | 11 s (download+verify+extract) |
| P2P listening | ~5 s after boot | ~5 s |
| RPC bound | 0.5 s after download gate | 5 s after boot |
| headers | 416k in 129 s | inline |
| block download | 719k blocks in 19.5 h, **11.1 MB/s flat** (pre-EMA baseline) | 21.0 h (04:39 Sep5 → 01:40 Sep6) |
| UTXO build | 4.5 h bulk catch-up @ 60.6 blk/s, full script verify, concurrent with download completing | inline (validation-bound; total 21 h end-to-end) |
| end-to-end to tip | 24.1 h (965,565) | 21.0 h (965,702) |
| serve during sync | ✅ 101+ inbound accepts; frame-for-frame handshake parity with Core (probe, fixed tool) | ✅ |

Core's 21 h wall vs bmc's 24.1 h: same order; bmc's split shows download at
11 MB/s was the constraint (network/peers, disk idle), and the two
known fixes landed mid-run (byte-floor: pre-EMA baseline; EMA peer claim +
TXOQ-1/SC1/CSI-1/CSI-2 now merged to main) — the optimized re-run gets a
clean measurement on both halves.

## Defects found by this benchmark (all fixed & merged to main, PR #2 a667e81, unless noted)
1. **byte floor unreachable early-chain** (7f4adcf): 77 KB/s vs 11.1 MB/s — 140x
2. **inbound probe tool broken** (1596697): no pong keepalive, sentinel collision, relay flag, reversed-magic footgun — the "bmc ignores strangers" finding was the tool, not the node
3. **EMA speed-ranked peer claiming + peers.good data-loss** (5fb5102)
4. **CSI-1 gettxoutsetinfo silent tip-for-height** refusal (7bf5e3f)
5. **TXOQ-1 gettxout blackout during catch-up** — between-block quiescent hook (1fa503b)
6. **SC1 shutdown-window accept** refused, Core-shaped (6eed1f1)
7. **CSI-2** one-record coinstats: documented limitation + seam (1cd7a0c); feature with audit session
- Open: **RPC-1** handler deadline (audit session, rpc_server.c lane)

## Process corrections logged
- False PASS (empty==empty) and false FAIL (watcher parser) both caught,
  retracted, and corrected by manual capture under the strict non-empty rule.
- Live proofs for TXOQ-1/SC1 deferred to next sync (documented).

## Artifacts
Public repo: benchmarks, gate tables, correction ledger, logs, scripts,
plans (PERF_PLAN / PEER_PLAN / ASSUMEUTXO_PLAN). Full datadirs archived:
`/mnt/archive/bmc-bench-20260906T015520` and
`/mnt/archive/core-bench-20260906T015520` (SSD freed for the optimized
re-run).
