--- a/asm/tests/test_utxo_catchup_shutdown.c
+++ b/asm/tests/test_utxo_catchup_shutdown.c
@@ existing shutdown-during-catchup harness (TXOQ-1 corner) @@
     /* Existing: arms catch-up, sends SIGTERM mid-batch, asserts the child
      * exits cleanly at a checkpoint boundary with the applied-height file
      * persisted. TXOQ-1 addition: while the SAME catch-up is running, a
      * second thread (standing in for the RPC side of the txoq socketpair)
      * issues utxo_live_lsm_get queries at ~10ms cadence. Before TXOQ-1
      * every one of those either timed out or saw the pre-catch-up state;
      * after the between-block hook, a coin created by a block the child has
      * ALREADY checkpointed must answer found=1 within one block interval
      * (~0.1s) of the child's progress reaching it -- proof the query was
      * served from inside the catch-up, not after it returned.
      *
      * Implementation notes for whoever lands this:
      - harness already forks a child running utxo_live_catchup on a synth
        datadir; parent side already has a poll loop on the applied-height
        file (mirror it as the hook's "progress" signal in the parent)
      - the query thread calls utxo_live_lsm_get against a READ-ONLY
        utxo_lsm_reload of the same files (the same view txoq_service uses)
      - assert: coin(txid of block N's output, vout 0) found once
        applied_height >= N, observed strictly BEFORE the child exits
      - assert no crash: the reload-in-progress guard means a query may be
        skipped at a boundary (returns not-ready), never served torn */
