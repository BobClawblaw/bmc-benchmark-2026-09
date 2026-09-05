# Post-run corrections to bmc's benchmark record (2026-09-05 14:55 UTC)

The benchmark ran on the PRE-FIX codebase; every fix made after is recorded
here so the bmc results read with their correct current state. The numbers
themselves (timings, gates, parity) stay valid — each row says what changes
and what doesn't.

| bmc record row | what was fixed after | effect on the record |
|---|---|---|
| gate: "stranger-handshake probe FAIL (0 replies)" | the probe tool: no pong keepalive (node timed it out ~72s mid-drain), sentinel collision, relay flag, reversed-magic footgun. Merged to main `1596697`, verified: full report vs live bmc (handshake ok, ping→pong, getaddr→addr, headers, inv, notfound×4, wtxidrelay/sendaddrv2 accepted+offered) | RETIRED — it was never a bmc defect; bmc answers frame-for-frame like Core |
| analysis finding #2 "probe FAIL filed" | superseded by probe1-probe4 analysis + corrected README gate (done) | closed |
| gate: "muhash parity BLOCKED under store load" (was: PASS on quiesced store) | UPDATE 15:24 UTC: CSI-1/TXOQ-1/SC1 MERGED to main via PR #2 (a667e81) + ledger; RPC-1 still in-flight with the audit session (their rpc_server.c lane) | unchanged: parity itself is PASS (three-way, strict rule); the BLOCKED note describes the loaded-RPC condition, which stands until TXOQ-1/RPC-1 land |
| gettxout under load | TXOQ-1 filed (parent's 60s WAL re-drain cadence); correct end-state sketched (answer in the worker service point) | open; does not affect the parity or timing numbers |
| download-rate record (11.1 MB/s flat) | EMA speed-ranked peer claiming merged to main (`5fb5102`) after the run | the recorded rate was achieved WITHOUT EMA — it is the pre-EMA baseline; the next run measures the EMA delta |
| boot child deaths "8/53 handshake failed" | re-diagnosed: serve_child store_init race during shutdown window (SC-1), not UTXO-store; errno logging + refuse-accept-during-shutdown sketched | the original RPC-2 diagnosis was wrong and is withdrawn (corrected in RPC_DEFECTS_CORRECTED.md); SC1 remains open, low severity (server survived, peer got nothing) |
| "coinstats re-seed status unconfirmed" (finding #3) | the clean-restart logs show coinstats adopted after re-seed (height reached, heartbeat normal) | CLOSED as working-as-designed (pre-BIP34 invalidation → re-seed → adopt) |

Code-state confirmation (all on origin/main as of today):
`1596697` probe fix (pong x3), `5fb5102` EMA + peers.good fix (dlc_pick_peer
x3), byte-floor fix + benchmark dir + identity scrub (merged earlier), and
the audit session's subsequent commits on top.

Re-run plan (with the optimized build): fresh datadirs, same harness; gates
expected to change: probe gate PASS expected, gettxout-under-load measured,
EMA-vs-baseline download delta measured.
