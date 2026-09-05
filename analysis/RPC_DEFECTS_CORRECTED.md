# RPC/Serve defects — corrected after full code reading (2026-09-05 05:00 UTC)

Supersedes the pre-fix claims in RPC_DEFECTS.md where wrong. Read the real
code first; several of my earlier "findings" mis-attributed the cause.

## What is actually true

1. ARCHITECTURE: the serve parent does not own the UTXO store; the download
   worker process does. gettxout answers via an IPC poll (txoq) to the
   worker; gettxoutsetinfo is served by a read-only LSM reload in the
   parent (utxo_setinfo_rpc.c, utxo_lsm_reload_ro + utxo_lsm_walk).
   utxo_live_init failure kills only the worker child (parent reaps ->
   exits non-zero -> systemd restarts). That part of the design is sound.

2. RPC-1 (CONFIRMED, unchanged): rpc_http_run applies rpcservertimeout to
   the socket/IO path only; rpc_dispatch/handler calls have NO wall-clock
   guard. A gettxoutsetinfo reload+walk on 165M coins (measured 60-83 s
   reload + walk; minutes-to-hours under writer contention) parks an RPC
   worker. Fix = cooperative deadline per request + deadline polls in the
   set-info walk. Anchored sketch: analysis/rpc1-*.patch.

3. RPC-3 (CORRECTED — this is the real bug): utxo_lsm_reload_ro is NOT
   lock-free as its own docs imply — the drain path contends with the
   worker's WAL writer slot; against a live datadir it either blocks in the
   drain or fails. Consequences:
     - the gettxoutsetinfo RPC path stalls (misread earlier as "hang on
       store open"; the open is O_RDONLY, it's the drain that blocks),
     - every offline tool (utxo_setinfo --muhash, dump_keys, probe_one)
       calling _ro against a live store fails/hangs — the "offline
       fallback" is NOT safe against a live store, contrary to its
       documented promise.
   Fix: true snapshot semantics for _ro (open WAL+manifest RO, replay
   [runs + WAL up to log_len-at-open], no writer slot needed) — anchored
   sketch analysis/rpc3-reload_ro-live-read.sketch.patch, with the asm+test
   plan spelled out. Interim acceptable: RPC-1's deadline so callers get a
   timeout instead of a hang.

4. RPC-2 (WITHDRAWN as diagnosed): "8/53 inbound children died on
   store-open contention" is WRONG — serve children never open the UTXO
   store; gettxout goes via IPC to the worker. The deaths are a separate
   defect: the child's store_init(store_buf) in serve_child.c:105 —
   reproduced live THIS MORNING (a peer connect logged
   "FATAL: store_init failed after 3 attempts" from serve_child.c:105,
   child died, server survived). That's a per-peer store-init failure
   (mmap pressure? index.dat? — needs its own diagnosis), NOT UTXO-related.
   The stranger-handshake probe's "0 replies" is likewise NOT explained by
   UTXO — child store_init dying or the probe's expectations are the two
   remaining candidates. New finding filed; corrected diagnosis matters
   because the earlier version pointed the fix at the wrong file.

## Reproduced this hour (live evidence, console.log preserved)
- 05:00 UTC: SIGTERM to worker + parent; clean boot of the fixed daemon;
  inbound child death with "store_init failed after 3 attempts"
  (serve_child.c:105) on the very first foreign peer connect.
- Server process unaffected; listener keeps accepting.

## Priority once main settles
1. serve_child store_init failure (breaks inbound serving — highest user
   impact, easiest mystery: three attempts failed, what's the errno? add
   the strerror and log, then fix).
2. RPC-1 handler deadline (protects the whole RPC surface under load).
3. RPC-3 reload_ro snapshot (unblocks offline tools + live gettxoutsetinfo).
