# Summary

The active workflow docs now require visual PNG inspection as part of run
verification.

- Single runs: inspect the full standard image set.
- Large batches: inspect representative best / typical / worst / outlier cases
  and record what was checked.

This closes the gap where agents could previously claim completion based only
on files existing on disk.
