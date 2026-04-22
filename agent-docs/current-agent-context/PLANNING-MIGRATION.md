# Remaining `.planning/` Migration

This file records the disposition of the final `.planning/` artifacts that remained after the first GSD-offboarding pass.

## Disposition by artifact

### `.planning/milestones/v1.0-REQUIREMENTS.md`

- Decision: historical only
- Rationale: shipped visualization-milestone requirements; no longer active agent context
- Destination: `docs/planning-history/milestones/v1.0-REQUIREMENTS.md`

### `.planning/milestones/v1.0-ROADMAP.md`

- Decision: historical only
- Rationale: shipped visualization roadmap; useful for history, not for present execution
- Destination: `docs/planning-history/milestones/v1.0-ROADMAP.md`

### `.planning/quick/260331-gh0-fix-sweep-methodology-time-window-formul/*`

- Decision: keep distilled technical content
- Rationale: contains still-relevant sweep-windowing methodology
- Active migration target: `agent-docs/current-agent-context/METHODOLOGY.md`
- Historical destination: `docs/planning-history/quick/260331-gh0-fix-sweep-methodology-time-window-formul/`

### `.planning/quick/260405-ke9-practical-assessment-of-spectral-phase-s`

- Decision: delete empty stub
- Rationale: no files, no preserved content

### `.planning/quick/260415-u4s-benchmark-threading-opportunities-across/*`

- Decision: keep distilled technical content
- Rationale: contains still-relevant threading benchmark conclusions
- Active migration target: `agent-docs/current-agent-context/METHODOLOGY.md`
- Historical destination: `docs/planning-history/quick/260415-u4s-benchmark-threading-opportunities-across/`

### `.planning/quick/260416-gcp-setup/*`

- Decision: keep distilled operational content
- Rationale: split-host compute setup is still live, but provisioning details are historical
- Active migration target: `agent-docs/current-agent-context/INFRASTRUCTURE.md`
- Historical destination: `docs/planning-history/quick/260416-gcp-setup/`

### `.planning/quick/260420-iwc-sync-phase22-artifacts/*`

- Decision: historical only
- Rationale: one-time Mac↔VM `.planning` sync and integration workflow; not part of the new system
- Destination: `docs/planning-history/quick/260420-iwc-sync-phase22-artifacts/`

### `.planning/quick/260420-oyg-independent-numerics-audit-of-fiber-rama/*`

- Decision: keep distilled technical content
- Rationale: contains high-value numerics audit context, but in GSD quick-task form
- Active migration target: `agent-docs/current-agent-context/NUMERICS.md`
- Historical destination: `docs/planning-history/quick/260420-oyg-independent-numerics-audit-of-fiber-rama/`

### `.planning/quick/260420-rqo-fix-numerics-audit-bugs-pre-attenuator-e/*`

- Decision: keep distilled technical content
- Rationale: documents which numerics audit findings were fixed and regression-covered
- Active migration target: `agent-docs/current-agent-context/NUMERICS.md`
- Historical destination: `docs/planning-history/quick/260420-rqo-fix-numerics-audit-bugs-pre-attenuator-e/`

### `.planning/reports/20260405-session-report.md`

- Decision: historical only
- Rationale: session accounting/reporting, not actionable agent context
- Destination: `docs/planning-history/reports/20260405-session-report.md`

### `.planning/todos/pending/provision-gcp-vm.md`

- Decision: keep distilled operational content
- Rationale: provisioning checklist is historical, but the architecture rationale still matters
- Active migration target: `agent-docs/current-agent-context/INFRASTRUCTURE.md`
- Historical destination: `docs/planning-history/todos/pending/provision-gcp-vm.md`

### `.planning/phases/31-reduced-basis-and-regularized-phase-parameterization/`

- Decision: delete empty leftover directory
- Rationale: content already preserved under `docs/planning-history/phases/31-reduced-basis-and-regularized-phase-parameterization/`

## Result

After this migration, `.planning/` should no longer carry live agent context. Durable guidance lives in `agent-docs/current-agent-context/`, and raw historical artifacts live in `docs/planning-history/`.
