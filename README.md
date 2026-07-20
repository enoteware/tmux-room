# tmux-room

A small macOS/Linux CLI for finding and attaching to long-running tmux agent rooms.

It lists each room with its attached state, detected agent (`Claude`, `Codex`, `Grok`, or shell), and uptime. It is designed for SSH, Tailscale, Mosh, and mobile clients such as Termius.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/enoteware/tmux-room/main/install.sh | bash
```

Make sure `$HOME/bin` is in your `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
```

## Usage

```bash
tmux-room                 # interactive picker
tmux-room --list          # list without attaching
tmux-room my-session      # direct attachment
tmux-room --version
tmux-room --update
```

Detach with `Ctrl-b`, then `d`.

For Termius command snippets, disable **Close session after running**.

## Requirements

- Bash 3.2 or newer
- tmux
- Python 3 (agent process detection)
- curl or wget for self-update

## Cross-device model

A tmux session belongs to the host where it runs. Use SSH/Tailscale to reach that host, then run `tmux-room` there:

```bash
ssh my-mac-mini tmux-room --list
ssh -t my-mac-mini tmux-room knowledge-hub
```

## Development

```bash
bash tests/test.sh
shellcheck bin/tmux-room install.sh tests/test.sh
```

CI runs on both Ubuntu and macOS.

## License

MIT
