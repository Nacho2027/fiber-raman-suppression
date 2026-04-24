## Plan

1. Treat the MMF code and trust-instrumentation work as done.
2. Finish the missing science step on burst:
   - run `scripts/research/mmf/baseline.jl`
   - sync back `results/raman/phase36/`
   - inspect representative standard images
3. Use that run to answer three closure questions, not to open new sub-lanes:
   - does `GRIN_50`, `L=2 m`, `P=0.5 W` show trustworthy headroom?
   - does `:sum` remain the primary MMF objective?
   - is joint `{φ, c_m}` worth keeping active?
4. Close the mild `L=1 m`, `P=0.05 W` regime explicitly as a negative result.
5. Write one durable MMF summary that either:
   - promotes the aggressive baseline as the project's MMF starting point, or
   - parks multimode as low-priority if the aggressive rerun still disappoints.
