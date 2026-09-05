# RPC & serve-surface defects found by the 2026-09-04 benchmark
# (bmc fresh IBD, /mnt/2tbssd) — root-caused from source, fixes sketched

All findings below were reproduced in the live benchmark run and then
traced to source. Sketches live in analysis/*.sketch*.patch; they are
designs with exact anchors, not buildable diffs (kept off the fix branch
until the operator's optimized build lands).

## RPC-1 — no wall-clock bound on RPC *handlers*
`rpc_http_run(c, g_timeout_s, handler)` (rpc_server.c ~line 883) returns the
handler's result with NO deadline around the call. `rpcservertimeout` is
wired to the *socket/read* path (rpc_http_conn_set_timeout + the deadline
check in rpc_http_read_and_run), which covers IO stalls but not a handler
that blocks or walks forever. Measured: `gettxoutsetinfo` on the 165M-coin
set never returned; it parked a worker thread (16 max), and the benchmark's
parity gate died there. Fix: per-request cooperative deadline
(`rpc_set_deadline` at dispatch) + `rpc_deadline_expired()` polls inside
long walks (gettxoutsetinfo's entry loop; same pattern for future
scan/walk RPCs). Client-visible contract matches Core: answer, or a loud
RPC_INTERNAL_ERROR timeout — never a silent hang.

## RPC-2 — UTXO-store contention crashes inbound serve children outright
`utxo_store_open` → `utxo_lsm_open` returns STATUS_FAIL when the WAL drain
is held by the download worker, and BOTH open paths did `exit(1)`. For a
freshly-forked serve child, `utxo_live_init()` treats any non-zero as fatal:
`_exit(1)`. Measured at boot: 8 of 53 inbound connections died as
"handshake failed" — the child opened the store, the writer held the WAL,
the child vanished. At tip, the stranger handshake probe got 0 replies the
same way. The node *can* serve headers/blocks/filters without the UTXO
surface, so the child must degrade, not die: return without `utxo_live_ok`,
keep serving, retry the open (rate-limited) for UTXO-backed calls, which
already have a not-ready error path. Boot's own path keeps fail-fast.
This is also the fix for the "probe FAIL" gate on the benchmark README.

## RPC-3 (related, same root) — offline tools kill the daemon
The same `exit(1)` sites are reachable from the `utxo_setinfo` offline tool
and the gettxoutsetinfo RPC path; a failed READ must fail the CALLER.
Strict mode becomes the boot path's contract only (`g_store_open_strict`).

## Why the store-open failure happens (context, not a bug per se)
`utxo_lsm_open` drains the WAL into a fresh memtable and returns
STATUS_FAIL if the drain can't claim the writer slot (`utxo_lsm_open`'s own
comment documents this for reload callers). Callers then chose `exit(1)` —
a boot-appropriate response applied globally. The WAL holder is usually
sub-second, which is why a *retry* design is the right shape and why the
hang-vs-crash asymmetry (RPC path hangs on lock elsewhere? no — the RPC
worker hangs only because the handler then walks the set with the writer
churning; the child path *crashed*) took two separate fixes.

## Gate re-evaluation once a fixed build lands
Re-run in order: (1) boot + flood inbound during WAL-heavy catch-up → 0
child deaths; (2) stranger-handshake probe at tip → version+verack answer;
(3) `gettxoutsetinfo` at tip with rpcservertimeout=30 → hash or loud
timeout; (4) offline `utxo_setinfo --muhash` during a writer-busy window →
error reply, daemon survives; (5) parity vs oracle at the same height (the
muhash gate — pending for this run, see logs/parity.txt; offline walk at
tip is the fallback once the writer settles).
