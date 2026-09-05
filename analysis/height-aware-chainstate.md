# gettxoutsetinfo — why an RPC with an explicit height does NOT need Core's
# chainstatemanager, and what bmc must validate before honoring one.

Context: the bmc-vs-Core benchmark needs `gettxoutsetinfo muhash` from both
nodes at the same height. Core's v31.99 oracle answers it natively (two
chainstates, hash over the validated snapshot set). bmc's LSM store exposes
height as a field per entry, so a height-restricted hash looks like a pure
filter-scan. The trap is what "height" means.

## What Core actually does (verified in this repo's knowledge, worth restating)
- `gettxoutsetinfo <hash>` (height form) requires coinstatsindex. It hashes
  the chainstate as it was at that height — the index stores the MuHash
  digest incrementally at every height, so it's O(1).
- Core's height semantics come from the *chainstate evolution*, not from
  per-coin fields: the digest at height H is the accumulated result of
  applying and undoing real blocks. Reorgs are intrinsic — undo data drove
  the digest back and the fork drove it forward.

## Why bmc's naive scan is not equivalent
1. **Height field = last-writer's height.** A coin created below H but spent
   and recreated above H (reused outpoints don't exist, but the reverse
   does: coin created above H must not appear; coin created below H and
   *still* unspent appears — fine) — the real break is reorg history: if the
   LSM ever applied a forked block and later rewound, entries carry the
   fork height or the rewind height depending on write order. The current
   LSM WAL/undo path rewinds by *deleting the fork's outputs and restoring
   the pre-state from undo*, which restores the ORIGINAL height, so height
   is mostly sound — but "mostly" is not a consensus claim.
2. **The real hazard is tombstones.** A coin spent above H was *live at H*.
   LSM deletion is physical (tombstone), and the store's compaction may
   erase the pre-spend record entirely. Without a versioned/tombstone-aware
   walk, coins spent after H are MISSING from the height-H set — a silent,
   size-dependent wrong answer (small during normal days, huge across
   churned ranges like exchange hot-wallet rotations).
3. **No validation is free.** Even with correct tombstone semantics, a
   height-filtered set is only Core-comparable if the pre-H chain was fully
   connected *with scripts verified* — bmc's `assumevalid` skips evaluation
   below the anchor, and Core's *index* digest also only reflects what was
   connected; this matches for the digest math itself but NOT for
   "trust me the pre-H UTXO set is right."

## Proposed shape for bmc (matches Core's guarantee, cheaply)
- Make `coinstatsindex` incremental-MuHash **mandatory** on this daemon
  config, not optional. It already computes the rolling digest during catch-up.
  Then height-restricted gettxoutsetinfo answers from the index (O(1),
  exactly Core's design), and the answer is by construction the same object
  Core hashes. The LSM never needs versioned tombstones.
- Keep the LSM-walk path for `height: "none"` (today's behavior) and label
  its output clearly as store-derived rather than index-derived.
- Validation contract before trusting parity results:
  (a) index digest at height == live-set hash at tip (catch-up self-check;
      catches a mis-indexed run),
  (b) `utxo_setinfo --muhash` offline LSM walk at tip == RPC index value,
  (c) oracle at identical hash, and txouts must match too (txout count is
      the orthogonal check — two sets can share a count while differing in
      content, but equality of both is the strongest cheap signal).

## For the current benchmark specifically (the honest workaround)
bmc's node is tip-synced with no reorgs during the run; the LSM-walk hash at
TIP is therefore sound today regardless of the tombstone question (nothing
was deleted after tip). So the plan:
1. offline `daemon/utxo_setinfo --muhash` on the datadir (no store open
   contention with the RPC path? -> it does open the LSM; if it blocks on
   the writer, the clean window is after stopping the daemon, but we don't
   want to stop a tip node mid-benchmark — try first, it may succeed since
   the writer only holds the WAL during flushes).
2. oracle `gettxoutsetinfo muhash <same blockhash>`; require non-empty,
   matching muhash AND txouts.
3. Any mismatch: bisect at an earlier common height (the tool takes
   --exclude-genesis-coinbase and --settle-ms; the live set vs index
   self-check above pinpoints indexing vs consensus divergence).
