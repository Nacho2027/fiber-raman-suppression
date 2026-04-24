# Parallel Research Agent Prompts

These prompts are designed for three concurrent Codex research agents:

- multimode
- multivar
- longfiber

They are intentionally operational. Each prompt tells the agent:

- what to read first
- what files it owns
- where to run compute
- how to launch and poll runs
- how to react to bugs or ambiguous results
- when to continue exploring versus when to stop and summarize

Recommended compute split:

- multimode: permanent `fiber-raman-burst`
- multivar: ephemeral burst VM
- longfiber: ephemeral burst VM

With the current `C3_CPUS = 50` quota in `us-east5`, the intended safe mix is:

- `c3-highcpu-22` permanent burst VM
- `c3-highcpu-8` ephemeral for multivar
- `c3-highcpu-8` ephemeral for longfiber

Total: `38` C3 CPUs.

Do not run all three heavy lanes on the permanent burst VM.

Use these prompt files directly:

- [COMMON-SUPERVISION-RULES.md](/home/ignaciojlizama/fiber-raman-suppression/agent-docs/parallel-research-campaign/COMMON-SUPERVISION-RULES.md)
- [MMF-AGENT-PROMPT.md](/home/ignaciojlizama/fiber-raman-suppression/agent-docs/parallel-research-campaign/MMF-AGENT-PROMPT.md)
- [MULTIVAR-AGENT-PROMPT.md](/home/ignaciojlizama/fiber-raman-suppression/agent-docs/parallel-research-campaign/MULTIVAR-AGENT-PROMPT.md)
- [LONGFIBER-AGENT-PROMPT.md](/home/ignaciojlizama/fiber-raman-suppression/agent-docs/parallel-research-campaign/LONGFIBER-AGENT-PROMPT.md)
