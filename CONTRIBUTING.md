# Contributing

Issues and pull requests are welcome.

Before opening a PR, run:

```bash
bash tests/test.sh
shellcheck bin/tmux-room install.sh tests/test.sh
```

Keep the CLI compatible with Bash 3.2 because macOS ships an older Bash by default.
