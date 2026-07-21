# tmux-room

A device-aware macOS/Linux CLI for finding and attaching to long-running tmux agent rooms.

Designed for SSH, Tailscale, Mosh, and mobile clients such as Termius.

## What it shows

The default picker and `--list` stay compact, with one room per row:

```text
DEVICE: mini [local]
STATUS: CPU 12% load (0.96/8) · RAM 44% (13.9/31.3 GB)
/ search | c clear | arrows move | Enter inspect/attach | x close | q quit

#  P ROOM                       DRIVER               ATTENTION     WIN LAST ACTIVE      NOTE
 1  * kh-review                  codex                !needs_input    2 2026-07-20 01:42 Review requested
 2    release-check              claude-fable5-low    detached        1 2026-07-20 00:18
```

Select a room in the interactive picker to reveal its full detail card before attaching:

```text
ROOM DETAILS
  ROOM: kh-review [attached] · 2 windows · #1
    AGENTS: Claude · fable5 · effort low · started 2026-07-20 01:00 · running 42m; Codex · gpt-5.6 · effort medium · started 2026-07-20 01:34 · running 8m
    OPENED: 2026-07-20 00:55 · LAST ACTIVE: 2026-07-20 01:42
    REPO: knowledge-hub · BRANCH: feature/mobile-ui
    SUMMED RSS SNAPSHOT: 768 MB · PROCESSES SNAPSHOT: 3
    CONTEXT: unavailable (agent CLI does not expose it safely)
    PATH: /code/hub

Attach this room? [y/N]:
```

- Arrow-key navigation in interactive terminals (`↑`/`↓`, `Enter`, `x`, `q`)
- `/` search across room, driver, attention state, note, and working path
- Narrow, medium, and wide layouts that fit the detected terminal width
- Attention-first ordering for `needs_input` and `failed`, followed by pinned and recently active rooms
- Compact CPU-load and RAM status for each device
- Provider/model/effort labels such as `claude-fable5-low` when safely discoverable
- A once-daily cached release check that stays silent when current
- Compact room, state, window, and activity overview before selection
- Every active supported agent after selection
- Model when safely discoverable from process arguments or pane metadata
- Agent start time and process running time
- Room-opened and last-active timestamps
- Repository, Git branch, working path, and best-effort resource snapshot

Unknown agents and models are labeled honestly rather than guessed.

The public room metadata contract also reports a declared driver, lifecycle state, note, pinned flag, and protected flag. These values are never inferred from terminal text.

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
tmux-room --fleet         # searchable local and SSH-device picker
tmux-room --fleet-json    # versioned aggregate fleet document
tmux-room --inspect my-room
tmux-room --json           # stable, machine-readable local inventory
tmux-room --json my-room   # stable, machine-readable single-room inventory
tmux-room --new my-room --cwd /code/project --agent codex
tmux-room --rename my-room review-room
tmux-room --metadata review-room --state needs_input --note "Review requested"
tmux-room --cleanup-stale --days 14
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

Only use SSH targets you already trust. Device labels must start with a letter or number and may then contain letters, numbers, dots, underscores, or hyphens. SSH targets are validated separately and may include a user and host. Use an SSH config alias when a host needs a non-default port or other connection options.

Optionally set a friendly name for the current device:

```bash
mkdir -p ~/.config/tmux-room
printf '%s\n' devbox > ~/.config/tmux-room/device
```

List rooms across the local device and configured hosts:

```bash
tmux-room --all
```

`--all` keeps the original sequential device tables. For one responsive table and a shared search across every reachable device, use:

```bash
tmux-room --fleet
```

In an interactive terminal, `/` searches device, room, driver, state, note, and path. `Enter` inspects the selected immutable room identity, then asks before attaching. Without an interactive terminal, the same command prints a compact table. Every unreachable, unsupported, or invalid device gets its own status row, including on narrow terminals.

Attach through the registry:

```bash
tmux-room mini:kh-review
```

Inspect and terminate a remote room using the same double-confirmation flow on the destination device:

```bash
tmux-room --inspect mini:kh-review
tmux-room --json mini:kh-review
tmux-room --kill mini:kh-review
```

Remote inspect and JSON commands are read-only and use SSH batch mode without allocating a pseudo-terminal.

## Public JSON inventory contract

`tmux-room --json` emits the `tmux-room.inventory` schema. Consumers must check `schema_version` before reading fields. Version 1 has this shape:

```json
{
  "schema": "tmux-room.inventory",
  "schema_version": 1,
  "generated_at": 1784649600,
  "device": {
    "name": "devbox",
    "source": "local"
  },
  "rooms": [
    {
      "id": "$3",
      "name": "kh-review",
      "windows": 2,
      "attached": false,
      "created_at": 1784640000,
      "activity_at": 1784649000,
      "path": "/code/knowledge-hub",
      "metadata": {
        "driver": "codex",
        "state": "needs_input",
        "state_updated_at": 1784649300,
        "state_age_seconds": 300,
        "fresh": true,
        "note": "Review requested",
        "pinned": true,
        "protected": false
      }
    }
  ]
}
```

The `id` is the raw immutable tmux session ID. Consumers should use it for mutation and revalidate both ID and name before destructive work.

The JSON inventory reads tmux session fields, the first pane working directory, and the public options documented below. The `path` field is the absolute current working directory reported by tmux for the first pane. It does not read pane contents or process environments. Control characters and bidirectional formatting controls in externally written metadata are removed before display or JSON encoding.

## Aggregate fleet JSON contract

`tmux-room --fleet-json` emits the `tmux-room.fleet` schema. `tmux-room --all --json` is an alias. Version 1 has this shape:

```json
{
  "schema": "tmux-room.fleet",
  "schema_version": 1,
  "generated_at": 1784649600,
  "complete": false,
  "devices": [
    {
      "name": "devbox",
      "source": "local",
      "status": "reachable",
      "inventory_generated_at": 1784649599,
      "rooms": []
    },
    {
      "name": "mini",
      "source": "remote",
      "status": "unreachable",
      "error": "connection_failed",
      "rooms": []
    }
  ]
}
```

Consumers must check `schema_version`, then handle `reachable`, `unreachable`, `unsupported`, and `invalid` device statuses. `complete` is false if any configured device could not provide a valid inventory. Reachable devices contain the same whitelisted room objects as `tmux-room.inventory`.

Remote inventory uses SSH batch mode, no pseudo-terminal, and a hard wall-clock deadline for every device. The default deadline is 15 seconds and can be changed with `TMUX_ROOM_REMOTE_TIMEOUT_SECONDS` from 1 to 300 seconds. Each response must be valid version 1 inventory JSON within the configured size limit. Set `TMUX_ROOM_REMOTE_MAX_BYTES` from 1024 to 16777216 bytes to change the default 4 MiB limit. Timeouts, connection failures, remote command failures, invalid JSON, unsupported schemas, duplicate identities, invalid types, control characters, and oversized responses become distinct device errors. Remote SSH targets, stderr, pane contents, and process environments are never copied into fleet JSON.

## Public room metadata

The shared tmux options are:

| Field | tmux option | Unset default |
| --- | --- | --- |
| Driver | `@tmux_room_driver` | `unknown` |
| State | `@tmux_room_state` | `unknown` |
| State timestamp | `@tmux_room_state_at` | no timestamp |
| Note | `@tmux_room_note` | empty string |
| Pinned | `@tmux_room_pinned` | `false` |
| Protected | `@tmux_room_protected` | `false` |

Metadata is advisory, not an authorization boundary. Any process or user with access to the tmux socket can change these options. Never put passwords, tokens, private prompts, or other secrets in a public room note.

Pinned and protected values use fail-closed exact semantics. An unset option, an explicitly empty value, or the exact raw value `0` is false. Every other stored value is displayed and exported as enabled, and the corresponding cleanup or termination guard remains active. `--unpinned` and `--unprotected` write an explicit per-room `0`, so global tmux defaults cannot keep either flag enabled.

Update metadata without attaching:

```bash
tmux-room --metadata kh-review \
  --driver codex \
  --state needs_input \
  --note "Waiting for review" \
  --pinned \
  --protected
```

Unset driver, state, and note values with `--clear-driver`, `--clear-state`, and `--clear-note`. Disable the per-room flags with `--unpinned` and `--unprotected`; these explicit false overrides take precedence over enabled global defaults. Each update snapshots exactly the requested options, targets the immutable session ID, and revalidates the room identity throughout the transaction. If a write fails, tmux-room restores the snapshot. `--state` writes the current epoch to `@tmux_room_state_at` before committing the new state; `--clear-state` clears both options.

Writable states are `running`, `idle`, `needs_input`, `failed`, `completed`, and `ended`. `unknown` is the honest unset or invalid fallback. `stale` is derived and cannot be written through the CLI.

By default, active states become `stale` when their timestamp is more than 300 seconds old. Set `TMUX_ROOM_STATE_TTL_SECONDS` to a positive number to change that threshold. Terminal states (`failed`, `completed`, and `ended`) remain terminal even when their timestamp is old. JSON always includes the timestamp, age, and `fresh` flag so clients can explain their decision.

## Room lifecycle

Create a detached room in an existing directory:

```bash
tmux-room --new kh-review --cwd /code/knowledge-hub
```

Add an allowlisted agent when desired:

```bash
tmux-room --new kh-review --cwd /code/knowledge-hub --agent codex --state running
```

Allowed agent names are `claude`, `codex`, `grok`, `gemini`, `cursor`, and `hermes`. The command must exist on `PATH`. Arbitrary shell command text is not accepted. When `--agent` is omitted, tmux starts the user's normal shell. When `--driver` is omitted, an explicit `--agent` also becomes the public driver value.

New and renamed rooms must start with a letter or number, followed only by letters, numbers, underscores, or hyphens. Periods are excluded because current tmux releases can rewrite them in session names. This keeps room references unambiguous across tmux-room, SSH, macOS, and web clients.

Creation captures the immutable ID directly from `tmux new-session`. Rename and metadata changes target that ID and verify it before and after mutation:

```bash
tmux-room --rename kh-review kh-review-done
```

## Guided stale cleanup

Review detached rooms that have been inactive for at least seven days:

```bash
tmux-room --cleanup-stale
tmux-room --cleanup-stale --days 30
```

Attached, pinned, and protected rooms are never candidates. Cleanup prints the complete candidate list and requires two exact confirmations: `CLEANUP <count>` and `KILL STALE`. Before each kill, it checks the immutable ID, name, attached state, exact activity timestamp, pinned flag, and protected flag. It repeats those checks after the final resource snapshot. A final tmux-side predicate requires the same activity timestamp, detached state, and false pinned and protected options. Only its true branch queues the immutable-ID kill. Any changed room or unreadable guard is skipped.

## Safe room termination

`tmux-room --kill` prints the complete room card before doing anything, including a best-effort descendant-process snapshot. The RAM figure is **summed RSS**, so shared pages may be counted more than once; it is a pressure indicator, not exact physical memory attribution. Summed RSS is marked `[ELEVATED]` at 1 GB and `[HIGH]` at 4 GB.

Termination requires both:

1. Type the exact room name.
2. Type the uppercase word `KILL`.

The inspected tmux `#{session_id}` is captured before confirmation and revalidated immediately before termination. Guard reads fail closed. A final tmux-side predicate requires the immutable ID and a false protected option. Only its true branch queues the kill. A replacement room reusing the same name is not killed. A final best-effort process/RSS snapshot is also taken immediately before the command. tmux may not terminate detached, daemonized, reparented, or signal-ignoring descendants. Model context usage is displayed only when it can be read safely and reliably; otherwise the UI says `CONTEXT: unavailable`.

A room with `@tmux_room_protected=1` cannot be killed directly or through stale cleanup. Clear protection explicitly with `tmux-room --metadata <room> --unprotected` before termination.

A tmux session remains on the host where it was created; `tmux-room` provides a consistent control surface across those hosts.

## Model detection

`tmux-room` reads process arguments and tmux pane command/title metadata. It does **not** inspect pane contents or process environment variables because those can contain secrets. If an agent does not expose its model safely, the UI displays `model unknown`.

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
