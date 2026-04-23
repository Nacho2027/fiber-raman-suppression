## Plan

1. Add MMF-only trust helpers:
   - conservative time-window recommendation / auto-upsize
   - trust metrics for boundary energy and per-mode Raman fractions
   - saved cost summaries across `:sum`, `:fundamental`, `:worst_mode`
2. Add tests for the new MMF-only behavior.
3. Run the relevant MMF test suite locally.
4. Stage the workspace to burst and run a focused MMF baseline matrix in a regime sweep plus cost-variant comparison.
5. Write a concise human-facing MMF summary under `docs/` with a practical recommendation.
