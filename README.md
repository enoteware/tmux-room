# tmux-room

A device-aware macOS/Linux CLI for finding and attaching to long-running tmux agent rooms.

Designed for SSH, Tailscale, Mosh, and mobile clients such as Termius.

## What it shows

The default picker and `--list` stay compact, with one room per row:

```text
DEVICE: mini [local]
  #  ROOM                             STATE     WINDOWS  LAST ACTIVE
  -- -------------------------------- --------- -------  ----------------
  1  kh-review                        attached        2  2026-07-20 01:42
  2  release-check                    detached        1  2026-07-20 00:18
```

Select a room in the interactive picker to reveal its full detail card before attaching:

```text
ROOM DETAILS
  ROOM: kh-review [attached] · 2 windows · #1
    AGENTS: Claude · claude-sonnet-4-6 · started 2026-07-20 01:00 · running 42m; Codex · gpt-5.6 · started 2026-07-20 01:34 · running 8m
    OPENED: 2026-07-20 00:55 · LAST ACTIVE: 2026-07-20 01:42
    REPO: knowledge-hub · BRANCH: feature/mobile-ui
    SUMMED RSS SNAPSHOT: 768 MB · PROCESSES SNAPSHOT: 3
    CONTEXT: unavailable (agent CLI does not expose it safely)
    PATH: /code/hub

Attach this room? [Y/n]:
```

- Compact room, state, window, and activity overview before selection
- Every active supported agent after selection
- Model when safely discoverable from process arguments or pane metadata
- Agent start time and process running time
- Room-opened and last-active timestamps
- Repository, Git branch, working path, and best-effort resource snapshot

Unknown agents and models are labeled honestly rather than guessed.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/enoteware/tmux-room/main/install.sh | bash
```

Make sure `$HOME/bin` is in your `PATH`:

```bash
export PATH="$HOME/bin:$PATH"
```

## Local usage

```bash
tmux-room                 # compact picker; selection reveals details before attach
tmux-room --list          # compact one-row-per-room table
tmux-room --kill my-room  # inspect RAM/processes, then double-confirm termination
tmux-room my-session      # attach locally
tmux-room --version
tmux-room --update
```

Detach with `Ctrl-b`, then `d`.

For Termius command snippets, disable **Close session after running**.

## Multi-device inventory

Create `~/.config/tmux-room/hosts`:

```text
mini elliot@mini.example.internal
devbox hostinger-vps
macbook my-macbook
```

Only use SSH targets you already trust. Host labels and targets are restricted to safe hostname characters.

Optionally set a friendly name for the current device:

```bash
mkdir -p ~/.config/tmux-room
printf '%s\n' devbox > ~/.config/tmux-room/device
```

List rooms across the local device and configured hosts:

```bash
tmux-room --all
```

Attach through the registry:

```bash
tmux-room mini:kh-review
```

Inspect and terminate a remote room using the same double-confirmation flow on the destination device:

```bash
tmux-room --kill mini:kh-review
```

## Safe room termination

`tmux-room --kill` prints the complete room card before doing anything, including a best-effort descendant-process snapshot. The RAM figure is **summed RSS**, so shared pages may be counted more than once; it is a pressure indicator, not exact physical memory attribution. Summed RSS is marked `[ELEVATED]` at 1 GB and `[HIGH]` at 4 GB.

Termination requires both:

1. Type the exact room name.
2. Type the uppercase word `KILL`.

The inspected tmux `#{session_id}` is captured before confirmation and revalidated immediately before termination. The final command targets that immutable ID, so a replacement room reusing the same name is not killed. A final best-effort process/RSS snapshot is also taken immediately before the command. tmux may not terminate detached, daemonized, reparented, or signal-ignoring descendants. Model context usage is displayed only when it can be read safely and reliably; otherwise the UI says `CONTEXT: unavailable`.

A tmux session remains on the host where it was created; `tmux-room` provides a consistent control surface across those hosts.

## Model detection

`tmux-room` reads process arguments and tmux pane command/title metadata. It does **not** inspect process environment variables because those can contain secrets. If an agent does not expose its model safely, the UI displays `model unknown`.

## Requirements

- Bash 3.2 or newer
- tmux
- Python 3.7+
- SSH for `--all` and remote attachment
- curl or wget for self-update

## Development

```bash
bash tests/test.sh
shellcheck bin/tmux-room install.sh tests/test.sh
```

CI runs on both Ubuntu and macOS.

## License

MIT
