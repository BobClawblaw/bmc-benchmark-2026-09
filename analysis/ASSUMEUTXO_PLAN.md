# ASSUMEUTXO_PLAN — snapshot adoption for bmc IBD (item 3)

Goal: match/beat Core's assumeutxo story — boot to *serving with a live UTXO
set* in minutes, background-downloading history.

## What exists in-tree already (verified 2026-09-04)
- bmc `dumptxoutset`: exports an assumeutxo snapshot in Core's format
  (BaseFastRandomAccessFile part files: U, C, D + chain-DB info).
- The LSM UTXO store has the load path that bulk mode already exercises
  (bulk_slots / bulk_blob ingestion, WAL checkpointing).
- Config keys: `bmc.bootcatchup` controls the download-first boot gate.

## Adoption sequence (the work)
1. Loader: consume Core-format snapshot parts -> LSM bulk build path.
   Snapshot UTXO count ~96M entries; measured bulk ingest (this run's
   download+verify combined rate implies the disk/CPU budget: seq-write
   0.4GiB/s SSD, 11MB/s blocks) -> expect ~2-5 min ingest, matching Core.
2. Validation layer: two chainstates (background below snapshot height H,
   normal above). The daemon already tracks tip, archive index and a
   separate headers.dat; add snapshot-height boundary: verification above H
   normal, archive fill below H proceeds as today; on background completion
   verify the historical chainstate's MuHash against the snapshot's.
3. Activation: RPC `loadtxoutset` (Core name) + config
   `assumeutxo=<hash>`; gettxout/gettxoutsetinfo answer from the active
   (snapshot) chainstate immediately; reindex-chainstate fallback intact.
4. Coinstatsindex + MuHash digest continuity: the snapshot carries Core's
   MuHash3072 — the parity check this project already uses becomes the
   adoption-time validation.

## Risks / honest notes
- Undo-data below H: bmc's undo_<h>.dat is built during catch-up; a
  snapshot boot has none below H until background sync fills it — fine for
  serving, but reorgs below H (practically never) must refuse until filled.
- The dual-chainstate bookkeeping is the bulk of the effort; everything
  else is wiring.
- Out of scope here: snapshot *generation* speed (dumptxoutset exists).

## Benchmark hook
The 2026-09-04 harness auto-measures both paths once `loadtxoutset` lands:
same datadir layout, oracle on the same box, phase stamps via
bmc_phase2_watch.sh. Target: boot -> RPC-serving-with-UTXO < 10 min on
/mnt/2tbssd vs Core's fresh genesis IBD (the queued core-bench run).
