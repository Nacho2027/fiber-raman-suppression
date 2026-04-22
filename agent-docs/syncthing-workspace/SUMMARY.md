# Summary

Syncthing is now installed and configured on:

- the Mac
- `claude-code-host`

The live sync model is:

- Mac `<->` `claude-code-host`: Syncthing working-tree sync
- git: history and GitHub pushes
- `fiber-raman-burst`: explicit `rsync` stage + explicit result pullback

Repo workflow docs were updated to describe that model, and `.stignore` now
declares the intended Syncthing exclusions for this repo.
