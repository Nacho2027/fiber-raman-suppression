# Context

The user asked for the human-facing documentation to be stripped of bloated,
AI-sounding prose and rewritten in a plainer style.

Scope for this pass:

- rewrite current Markdown docs that a lab user or maintainer is likely to open;
- keep generated PDFs, dirty TeX, and result artifacts untouched;
- keep deep `docs/planning-history/` files as archive records, but make the
  current docs stop pointing readers into them as normal onboarding material;
- keep agent-only operating material out of the public docs surface.

Writing rules used here:

- lead with the next useful action;
- say what is supported and what is experimental;
- keep examples concrete;
- remove long throat-clearing, hype, and process narration;
- preserve hard numbers only where they change a decision.
