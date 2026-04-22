# Context

The project already mandates that optimization runs leave a standard PNG set on
disk, but "file exists" is not enough. The user wants a stronger rule: agents
must actually look at the generated figures before calling a run complete.

The rule needs to be strict enough to matter without becoming absurd for large
sweeps that emit hundreds of images.
