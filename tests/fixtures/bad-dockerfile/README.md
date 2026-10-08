# Fixture: bad-dockerfile

**Expected to be caught by:** `_docker.yml` (hadolint + dockle).

Uses `:latest`, runs as root, hard-codes a password env, missing apt-get update + cache cleanup, ADD over a URL, shell-form CMD.
