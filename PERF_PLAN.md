# Perf program vs Bitcoin Core — ranked, with owners and status

Derived from the 2026-09-04 /mnt/2tbssd benchmark (live data in
logs/, findings in analysis/PEER_ANALYSIS.md and worklog/2026-09-04.md).
Status tracked here; benchmark repo auto-ticks refresh the evidence.

| # | item | state |
|---|---|---|
| 1 | dl_catchup peer-floor fix (Rule C) — fresh IBD 77KB/s -> 11MB/s | DONE, on fix/dlc-peer-floor-depth; merge into main pending (other session) |
| 2 | assumevalid default-on run (Core semantics; already implemented) | TODO: next fresh sync runs with Core's default assumed-valid — measure the download-bound end-to-end |
| 3 | assumeutxo snapshot adoption (consume Core's, serve our own) | TODO: the structural IBD win |
| 4 | speed-ranked peer selection (EMA from the /proc samples already taken; claim fastest-first; cross-run book ranking) | TODO: sketched in PEER_ANALYSIS.md |
| 5 | BIP152 compact-block prefetch for the last ~144 blocks; per-peer getdata batching | TODO |
| 6 | full-verification chart: bmc parallel taproot (26.6 eff cores) vs Core, assumevalid=0 from genesis | TODO: one run after parity passes — the headline differentiator |
| 7 | serve-phase comparison (bmc inbound-serve-at-boot vs Core post-IBD) | AUTO: this benchmark's monitors stamp it; Core phase auto-launches at bmc's RESULT |

What we are NOT doing (measured, not guessed): disk micro-opt (SSD idle at
0.4GiB/s vs 5MB/s writes), worker-count inflation (peer quality binds,
floor-hunt A/B proved it).
