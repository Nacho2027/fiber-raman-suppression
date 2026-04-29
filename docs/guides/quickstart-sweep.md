# Quickstart: Sweep

Sweeps are heavy. Run them on `fiber-raman-burst`, not on `claude-code-host`.

## List sweeps

```bash
julia -t auto --project=. scripts/canonical/run_sweep.jl --list
```

## Stage to burst

From the editing host, sync the checkout to burst with the project rsync recipe,
then launch through the heavy wrapper:

```bash
burst-ssh "cd fiber-raman-suppression &&   ~/bin/burst-run-heavy B-sweep   'julia -t auto --project=. scripts/canonical/run_sweep.jl smf28_hnlf_default'"
```

Pull `results/` back explicitly when the run finishes. Syncthing will then move
those files between the Mac and `claude-code-host`.

## After the run

```bash
julia -t auto --project=. scripts/canonical/index_results.jl --compare --top 10 results/raman
```

Inspect representative images: best, typical, worst, and any outliers. Record
what you checked in the agent summary or in the report that uses the data.

Always stop the burst VM when finished.
