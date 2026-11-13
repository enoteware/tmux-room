# tmux-room

A device-aware macOS/Linux CLI for finding and attaching to long-running tmux agent rooms.

Designed for SSH, Tailscale, Mosh, and mobile clients such as Termius.

## What it shows

The default picker puts room names first, highlights the selection, and keeps
keyboard controls at the bottom. Its list scrolls within the terminal height;
narrow windows use two lines per room. A selected-room detail area appears when
there is enough space. Press `w` to open the live overview.

`--list` keeps the compact one-row-per-room table:

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

The public room metadata contract also reports a declared driver, bot owner and owner ID, lifecycle state, note, pinned flag, and protected flag. These values are never inferred from terminal text.

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
tmux-room --open          # menu: client, agent, model; create, /start, attach
tmux-room --list          # compact one-row-per-room table
tmux-room --fleet         # searchable local and SSH-device picker
tmux-room --watch         # live, responsive grid of local and SSH rooms
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

Each device needs its own `hosts` file listing the *other* devices, and each needs `tmux-room` installed: remote inventory is collected by running `tmux-room` on the destination over SSH. `--all` runs `--list` there and prints the result; `--fleet` runs `--json` and merges it into one table.

`--all` keeps the original sequential device tables. For one responsive table and a shared search across every reachable device, use:

```bash
tmux-room --fleet
```

In an interactive terminal, the status line carries an update notice when a newer GitHub release exists, `/` searches device, room, driver, state, note, and path. `Enter` inspects the selected immutable room identity, then asks before attaching. `x` closes the selected room through the double-confirmation flow described in [Safe room termination](#safe-room-termination); a room on another device is confirmed on that device over SSH. Closing a room makes the snapshot stale, so the picker collects a fresh inventory before it redraws. Without an interactive terminal, the same command prints a compact table. Every unreachable, unsupported, or invalid device gets its own status row, including on narrow terminals.

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

## Live room overview

Run `tmux-room --watch` (or `--god`) to observe several rooms at once. The grid
uses the terminal's current width and height and rearranges when the window
resizes. Extra rooms continue on another page so previews stay readable.

Each tile shows the device, room, declared agent, attention state, and a live
snapshot of the room's active pane. This explicit view reads terminal contents;
ordinary inventory and JSON commands remain metadata-only. Previews stay in
memory and do not attach to, resize, or send input to the source terminals.

Tiles have borders and contrasting status badges. The selected tile has a clear
highlight. Colors fall back to terminal emphasis when `NO_COLOR` is set or colors
are unavailable.

Use the arrow keys to select a tile, Enter to confirm attachment, `/` to search,
`c` to clear the search, and `a` to toggle rooms needing attention. Press `s` to
open the room chooser: type to find a room, move with arrows, and press Enter to
swap it into the selected position. Swaps affect the overview layout only and
stay in place across inventory refreshes for this view.

Press `g` to return to the room picker. `q` closes the overview, returning to the
picker when opened with `w`.
Use Page Up and Page Down to change pages, and `r` to refresh the fleet. Detach from an attached
room with `Ctrl-b`, then `d`.

The overview uses the same configured SSH hosts as the fleet picker. Slow or
unavailable rooms show their status while the rest of the grid stays usable.
Remote machines need Python 3 and tmux, but do not need a new tmux-room version
for previews. Requires an interactive terminal with Python's curses module.

## Client and project emoji

Give each client or project a glyph in `~/.config/tmux-room/emoji`, one
`<prefix> <emoji>` pair per line. Blank lines and `#` comments are ignored.

```text
# client / project emoji
natural-catch  🐟
propfirms      📈
beat-buddies   🎵
brain          🧠
```

Rooms then carry their client's glyph everywhere a room list is drawn: the local
table, the arrow picker, and the cross-device fleet picker.

```text
#  P SERVER   ROOM                             ATTENTION
  1   🟩 dev   🐟 natural-catch-pdp              stale
  2   🟩 dev   📈 propfirms-arrows               detached
  3   💻 mbp   🧠 brain-review                   attached
  4   🍎 mini  🎵 beat-buddies-ship              completed
```

A prefix matches when the room name equals it, or starts with it and the next
character is not a letter or digit. So `brain` tags `brain-review` and
`brain_macbook_report` but leaves `brainstorm-notes` bare. When several prefixes
match, the longest one wins.

The glyph is display only. Attaching, searching, `--json`, and `--inspect` all
use the real room name, so `tmux-room natural-catch-pdp` keeps working unchanged.

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
        "owner": "Review Bot",
        "owner_id": "review-bot",
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
| Owner | `@tmux_room_owner` | empty string |
| Owner ID | `@tmux_room_owner_id` | empty string |
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
tmux-room --new kh-review --cwd /code/knowledge-hub --agent grok --model grok-4.6 --start
```

Allowed agent names are `claude`, `codex`, `grok`, `gemini`, `cursor`, and `hermes`. The command must exist on `PATH`. Arbitrary shell command text is not accepted. `--model` only accepts a token of letters, numbers, dots, underscores, colons, slashes, or hyphens. `--start` sends the hardcoded `/start` prompt. It does not accept custom prompt text. When `--agent` is omitted, tmux starts the user's normal shell. When `--driver` is omitted, an explicit `--agent` also becomes the public driver value.

Declare a bot owner when creating a room:

```bash
tmux-room --new bot-review --owner "Review Bot" --owner-id review-bot
tmux-room --metadata bot-review --owner "Release Bot" --owner-id release-bot
tmux-room --metadata bot-review --owner "" --owner-id ""
```

Owner names have control characters removed and surrounding whitespace trimmed, then must be at most 64 characters. Owner IDs must match `[A-Za-z0-9][A-Za-z0-9._:@-]{0,63}`. `--owner-id` requires `--owner` in the same command. Empty values clear ownership; clearing the owner also clears its ID. Changing an existing owner without `--owner-id` clears the previous ID; setting the same owner again preserves it. Owners appear in room details, JSON metadata (`owner` and `owner_id`), and the existing note space in wide lists. Narrower lists add an owner line only for owned rooms. Wide lists also use an owner line when needed to preserve the visible note. Long owner labels are truncated with an ellipsis to fit the terminal. Unowned rooms keep their existing layout.

## Launch wizard

`tmux-room --open` (also `--launch`) asks three questions, then creates the room and attaches:

1. Client
2. Agent (`claude`, `codex`, `grok`, and the others on PATH)
3. Model for that agent

Enter accepts the last choice for that client. The room name is `{client}-{agent}`. If that room already exists, tmux-room attaches it. `--fresh` makes `{client}-{agent}-2` instead.

The client menu is grouped by Invoi client id (`128  CS  California Strategies`). Starred Invoi clients are marked with `*` and listed first. Extra local stars live in `~/.config/tmux-room/favorites` (one id or slug per line). Git worktrees are skipped. If one client has more than one checkout, a second repo menu appears. Internal tools and other folders without an Invoi id still show after the Invoi clients.

Optional path pins live in `~/.config/tmux-room/clients`:

```text
regably /home/elliot/code/regably
128 cal_strat /home/elliot/code/cal_strat
```

Last client, last agent, and per-client defaults are stored in `~/.config/tmux-room/launch`. `--open` sends `/start` so Claude runs the session-start workflow. Other agents get the same first prompt.

Skip the menus when you already know the answers:

```bash
tmux-room --open --client 128 --agent grok --model grok-4.6
tmux-room --open --client regably --agent grok --model grok-4.6
```

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

The same two confirmations run behind the `x` key in both interactive pickers, so there is no faster path to killing a room. In the fleet picker, `x` on a remote row opens an SSH session and the destination device asks for both confirmations itself. The immutable tmux `#{session_id}` travels with the room name, so a replacement room that reused the name is not killed by a stale selection. This requires tmux-room 0.7.0 or newer on the destination device.

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
