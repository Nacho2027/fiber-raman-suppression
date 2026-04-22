# Context

The user wants the Mac and the always-on VM to behave like one continuous
workspace instead of using git as the transport layer between machines.

That requires three explicit decisions:

1. Mac and `claude-code-host` should be kept in live sync with Syncthing.
2. `.git` should stay out of Syncthing. Git remains for history and pushes, not
   for live file transport.
3. `fiber-raman-burst` should stay outside the Syncthing mesh and continue to
   use explicit staging and result retrieval.
