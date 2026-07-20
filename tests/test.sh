#!/usr/bin/env bash
set -eo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/bin/tmux-room"

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_contains() {
  case "$1" in *"$2"*) ;; *) fail "expected output to contain: $2\nactual:\n$1";; esac
}
assert_not_contains() {
  case "$1" in *"$2"*) fail "expected output not to contain unsafe value";; *) ;; esac
}

bash -n "$SCRIPT"
[[ "$($SCRIPT --version)" == "tmux-room 0.2.1" ]] || fail "version should be 0.2.1"
help=$($SCRIPT --help)
assert_contains "$help" "--all"
assert_contains "$help" "device:room"
assert_contains "$help" "--kill"

MOCK=$(mktemp -d)
trap 'rm -rf "$MOCK"' EXIT

cat > "$MOCK/tmux" <<'EOF'
#!/usr/bin/env bash
[[ -n "${TMUX_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$TMUX_MOCK_LOG"
case "$1" in
  has-session) exit 0 ;;
  list-sessions)
    echo 'alpha|2|1|1700000000|1700003600|$1'
    ;;
  display-message)
    display_id="${TMUX_REVALIDATE_ID:-\$1}"
    if [[ -n "${TMUX_ID_COUNTER:-}" ]]; then
      count=0
      [[ -f "$TMUX_ID_COUNTER" ]] && read -r count < "$TMUX_ID_COUNTER"
      count=$((count + 1))
      printf '%s\n' "$count" > "$TMUX_ID_COUNTER"
      if ((count >= 2)) && [[ -n "${TMUX_SECOND_REVALIDATE_ID:-}" ]]; then
        display_id="$TMUX_SECOND_REVALIDATE_ID"
      fi
    fi
    printf '%s|alpha\n' "$display_id"
    ;;
  list-panes)
    echo '4242|/work/knowledge-hub|node|review'
    ;;
  attach-session) exit 0 ;;
esac
EOF

cat > "$MOCK/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "${TMUX_ROOM_RESOURCE_SCAN:-}" == "1" && "${TMUX_ROOM_RESOURCE_REAL:-}" != "1" ]]; then
  printf '768\t3\n'
elif [[ "${TMUX_ROOM_AGENT_SCAN:-}" == "1" ]]; then
  printf 'Claude\tclaude-sonnet-4-6\t42m\t2026-07-20 01:00\n'
  printf 'Codex\tgpt-5.6\t8m\t2026-07-20 01:34\n'
elif [[ "${TMUX_ROOM_FORMAT_DATE:-}" == "1" ]]; then
  case "$TMUX_ROOM_EPOCH" in
    1700000000) echo '2023-11-14 22:13' ;;
    1700003600) echo '2023-11-14 23:13' ;;
  esac
else
  /usr/bin/python3 "$@"
fi
EOF

cat > "$MOCK/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *'rev-parse --show-toplevel'*) echo '/work/knowledge-hub' ;;
  *'branch --show-current'*) echo 'feature/mobile-ui' ;;
  *) exit 1 ;;
esac
EOF

cat > "$MOCK/hostname" <<'EOF'
#!/usr/bin/env bash
echo devbox
EOF

cat > "$MOCK/ssh" <<'EOF'
#!/usr/bin/env bash
[[ -n "${SSH_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$SSH_MOCK_LOG"
source_label=local
case "$*" in
  *TMUX_ROOM_SOURCE_LABEL=remote*) source_label=remote ;;
esac
printf 'DEVICE: mini [%s]\n' "$source_label"
echo '  ROOM: remote-review [detached] · 1 window'
echo '    AGENTS: Codex · gpt-5.6 · running 3m'
EOF

chmod +x "$MOCK"/*

TMUX_LOG="$MOCK/tmux.log"
output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$output" "DEVICE: devbox [local]"
assert_contains "$output" "#  ROOM"
assert_contains "$output" "alpha"
assert_contains "$output" "attached"
assert_contains "$output" "2023-11-14 23:13"
assert_not_contains "$output" "AGENTS:"
assert_not_contains "$output" "REPO:"
assert_not_contains "$output" "SUMMED RSS SNAPSHOT:"
assert_not_contains "$(<"$TMUX_LOG")" "list-panes"

: > "$TMUX_LOG"
picker_output=$(printf '1\nn\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$picker_output" "ROOM DETAILS"
assert_contains "$picker_output" "AGENTS: Claude · claude-sonnet-4-6 · started 2026-07-20 01:00 · running 42m; Codex · gpt-5.6 · started 2026-07-20 01:34 · running 8m"
assert_contains "$picker_output" "REPO: knowledge-hub"
assert_contains "$picker_output" "SUMMED RSS SNAPSHOT: 768 MB · PROCESSES SNAPSHOT: 3"
assert_contains "$picker_output" "Attach this room? [y/N]"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
printf '1\n\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" >/dev/null
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
printf '1\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" >/dev/null
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" alpha >/dev/null
assert_contains "$(<"$TMUX_LOG")" "attach-session -t =alpha"

: > "$TMUX_LOG"
printf '1\ny\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" >/dev/null
assert_contains "$(<"$TMUX_LOG")" "attach-session -t \$1"

: > "$TMUX_LOG"
attach_race_output=$(printf '1\ny\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" || true)
assert_contains "$attach_race_output" "Attachment aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

HOSTS="$MOCK/hosts"
SSH_LOG="$MOCK/ssh.log"
printf 'mini mini-host' > "$HOSTS"
all_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --all)
assert_contains "$all_output" "DEVICE: devbox [local]"
assert_contains "$all_output" "DEVICE: mini [remote]"
assert_contains "$all_output" "remote-review"
assert_contains "$(<"$SSH_LOG")" "TMUX_ROOM_SOURCE_LABEL=remote"

: > "$SSH_LOG"
PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" mini:alpha >/dev/null
assert_contains "$(<"$SSH_LOG")" "-t mini-host tmux-room alpha"

: > "$TMUX_LOG"
cancel_one=$(printf 'wrong-room\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha)
assert_contains "$cancel_one" "Kill cancelled"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
cancel_two=$(printf 'alpha\nNO\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha)
assert_contains "$cancel_two" "Kill cancelled"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
kill_output=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha)
assert_contains "$kill_output" "Killed room: alpha"
assert_contains "$(<"$TMUX_LOG")" "kill-session -t \$1"
assert_contains "$(<"$TMUX_LOG")" $'display-message -p -t =alpha #{session_id}|#{session_name}\nlist-panes -s -t $1 -F #{pane_pid}\ndisplay-message -p -t =alpha #{session_id}|#{session_name}\nkill-session -t $1'

: > "$TMUX_LOG"
race_output=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha || true)
assert_contains "$race_output" "Kill aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
ID_COUNTER="$MOCK/id-counter"
snapshot_race_output=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ID_COUNTER="$ID_COUNTER" TMUX_SECOND_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha || true)
assert_contains "$snapshot_race_output" "Kill aborted: room identity changed during final snapshot"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$SSH_LOG"
PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --kill mini:alpha >/dev/null
assert_contains "$(<"$SSH_LOG")" "-t mini-host tmux-room --kill alpha"

BAD_HOSTS="$MOCK/bad-hosts"
printf 'bad -oProxyCommand\n' > "$BAD_HOSTS"
bad_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$BAD_HOSTS" "$SCRIPT" --all)
assert_contains "$bad_output" "DEVICE: bad [invalid host entry]"

ESC=$(printf '\033')
C1=$(printf '\302\233')
BIDI=$(printf '\342\200\256')
dirty_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE="dev${ESC}]0;owned${C1}spoof${BIDI}rtl" "$SCRIPT" --list)
assert_not_contains "$dirty_output" "$ESC"
assert_not_contains "$dirty_output" "$C1"
assert_not_contains "$dirty_output" "$BIDI"

stale_output=$(printf '1\nn\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_RESOURCE_REAL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$stale_output" "SUMMED RSS SNAPSHOT: 0 MB · PROCESSES SNAPSHOT: 0"

cat > "$MOCK/ps" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$MOCK/ps"
unavailable_output=$(printf '1\nn\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_RESOURCE_REAL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$unavailable_output" "RESOURCE SNAPSHOT: unavailable"
rm "$MOCK/ps"

EMPTY="$MOCK/empty"
mkdir "$EMPTY"
cat > "$EMPTY/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "has-session" ]]; then exit 1; fi
exit 0
EOF
chmod +x "$EMPTY/tmux"
empty_output=$(PATH="$EMPTY:/usr/bin:/bin" TMUX_ROOM_DEVICE=empty "$SCRIPT" --list)
assert_contains "$empty_output" "DEVICE: empty [local]"
assert_contains "$empty_output" "No tmux rooms are running."

echo "tests passed"
