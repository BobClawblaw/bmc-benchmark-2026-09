# PEER_PLAN — speed-ranked peer selection for dl_catchup (item 4)

Evidence base: analysis/PEER_ANALYSIS.md + logs/floorhunt.log
(2026-09-04 run, same datadir, one peer pool):

  byte floor only          160k blk/240s  1.4MB/s
  block floor only         178k blk/240s  2.0MB/s
  Rule C (shipped)         live: 77KB/s -> 4.6 -> 11 MB/s as archive deepens
  AND-rule (regression)     77KB/s, 0 kills, 22/22 workers under floor

Rule C fixed eviction. Selection is still round-robin over the
confirmed-live pool: the parent samples every worker's real /proc io every
10s for the status display and then throws the numbers away. This is the
next tier.

## Design (minimal, no ABI churn)

1. Per-peer EMA, MAP_SHARED alongside the existing claimed[]/banned[]
   arrays: ema_bps[nlive], doubles, zero-init, written by the parent's
   existing 10s tick (it already computes delta/10 per worker; the peer
   index is stats[w].held_idx — the same value used for bans).
   alpha = 0.5, half-life ~20s; clamp tiny early-chain values against a
   depth-honest floor (compare in blocks/s too, as Rule C does).
2. Claim order: dlc_worker's peer search becomes "scan live[] for the
   highest-EMA unclaimed unbanned peer" instead of (slot+a)%nlive. nlive is
   <=2048; a linear scan per connection attempt is fine at connection rate
   (at most once per ~minutes per worker).
3. Cross-run memory: at catch-up end, persist the per-peer EMA into the
   existing peers.good mechanism's slot (dl_save_good_peers already
   round-trips the best deliverers). Upgrade peers.good to lines of
   "ip<TAB>ema_kbps", dl_load_good_peers parses both forms (old files stay
   valid, no header change). This makes run N+1 start with run N's speed
   knowledge — natural selection, no manual peer lists.
4. Optional (later): ASN/geography cap so one slow continent can't occupy
   more than ceil(nlive/3) workers; the geo audit showed HKG/CHN/KOR/RUS
   peers averaging 1.7-2.7 KB/s vs 6-12 KB/s for US on this host. Skip
   until 1-3 measured.

## Why this is safe
- It never picks a peer Rule C would kill: EMA only reorders *within* the
  confirmed-live, unbanned set; Rule C stays the eviction authority.
- Fresh syncs (no history) degrade to current behavior until the first
  tick populates EMA.
- Crash-safe: MAP_SHARED state dies with the process exactly like
  claimed[]/banned[] do today.

## Test
test_dialhelper-style corner: given ema[] = [10, 5, 9], claim order must be
peer0 then peer2 then peer1, skipping claimed/banned. Plus a regression
that the EMA file round-trips (old format + new format parse).
