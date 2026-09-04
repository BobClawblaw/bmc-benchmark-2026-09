# bmc vs Bitcoin Core IBD benchmark — /mnt/2tbssd (2026-09-04)

Status: **in progress**. bmc download phase restored to 4.6 MB/s after the
peer-floor regression was found and fixed; Core starts after bmc finishes.

## Layout
- Host: 32-core Linux 7.0.0-30, 60 GB RAM, dedicated 1.8 TB SSD (ext4,
  /dev/sdc3) mounted at /mnt/2tbssd.
- Oracle for tip height + UTXO-set parity: a long-synced Bitcoin Core
  v31.99 node on the same box (`gettxoutsetinfo muhash <hash>` comparison).
- bmc: cloned from https://github.com/BobClawblaw/bitcoinmachinecode —
  clone 8 s, build (`make daemon/bitcoind daemon/bitcoin_cli`, -j32) 8 s,
  0 warnings.
- Core v31.1: download 10 s (87 MB), sha256 check, extract 1 s.
- Disk baseline: 0.40 GiB/s seq write / 0.42 GiB/s cold seq read; 4k
  O_SYNC random-write test still running (disk is idle for this workload —
  write rate during sync is ~5 MB/s peak).

## The bmc story: 15x self-inflicted slowdown, found and fixed
1. Fresh run (commit f725cb7) reached 108k/416k blocks in 22 min but at
   **77 KB/s aggregate** — ~3 days projected for the full chain. Per-peer
   medians: 22/22 workers under the 32 KB/s dead-weight floor, **zero
   evictions in 20 min**. Peer pool geo: 7×US, 3×DE, one each CA/FR/BR/RU/
   KR/IE/HK/CN; the slowest peers (1.7–2.7 KB/s) were HKG/CHN/KOR/RUS/BRA.
2. The cause is `93fab72` (2026-09-02), which changed the dead-weight rule
   from a byte floor to `byte_rate < floor && blocks_this_tick < 10` to stop
   false bans of honest tiny-block peers. The AND makes the byte floor
   unreachable for the first ~150k blocks: 6–9 blocks/s of tiny blocks
   clears the block check while trickling below 32 KB/s, so nothing is ever
   evicted. (The earlier 017a83b tuning had measured 218 KB/s → 1.6 MB/s
   from aggressive eviction; 93fab72 quietly defanged it early-chain.)
3. A/B on the same datadir + peer pool, hole-restored 30k-block spans:
   | rule | aggregate | evictions |
   |---|---|---|
   | byte floor only (pre-0902) | 1.4 MB/s, 160k blocks/240 s | 2 |
   | current AND rule | 77 KB/s, 0 kills | 0 |
   | block floor only (≥10 blk/s or drop) | **2.0 MB/s, 178k blocks/240 s** | 3 |
4. Fix committed & pushed to github: `fix/dlc-peer-floor-depth` (2c6e989) —
   OR semantics: <10 blocks/tick is dead at any depth; otherwise the byte
   floor decides. The 0902 false-positive it was protecting against (an
   honest tiny-block peer at 50 blk/s / 20 KB/s) still passes: block floor
   says healthy, byte floor never runs. Re-measured live: **4.6 MB/s**, 3
   evictions in 7 min, progress 209k blocks in 7 min.

## Timings so far (bmc)
- start -> P2P listener bound: ~5 s; dns seeds + 143 peers: ~1 s more
- headers: 416,000 in ~129 s (~3,200 hdr/s) on the fixed run (first run's
  605 s included archive bookkeeping at a different tip)
- blocks: 965k span at 4.6 MB/s ≈ mid-2010s data, ETA ~2.5–3 h total
  (was ~3 days before the fix)
- RPC is not up yet because the fixed binary still sits in boot catch-up;
  measured live each cycle.

## Files
- logs/: session log, bmc phase/progress/bisect/floorhunt, Core stagger
- scripts/: install + benchmark + A/B + audit scripts used
- analysis/PEER_ANALYSIS.md: the peer-selection audit; dlc-peer-floor-fix.patch
