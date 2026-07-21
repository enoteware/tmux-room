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
assert_before() {
  case "$1" in *"$2"*"$3"*) ;; *) fail "expected $2 to appear before $3";; esac
}
assert_no_entry_with_prefix() {
  /usr/bin/python3 -c 'import os,sys; raise SystemExit(1 if any(name.startswith(sys.argv[2]) for name in os.listdir(sys.argv[1])) else 0)' \
    "$1" "$2" || fail "unexpected staging file with prefix $2"
}
assert_max_display_width() {
  printf '%s' "$1" | /usr/bin/python3 -c '
import re
import sys
import unicodedata

limit = int(sys.argv[1])
ansi = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
for number, raw in enumerate(sys.stdin.read().splitlines(), 1):
    line = ansi.sub("", raw)
    width = sum(0 if unicodedata.combining(ch) else 2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in line)
    if width > limit:
        raise SystemExit("line %d is %d columns, expected at most %d: %r" % (number, width, limit, line))
' "$2" || fail "output exceeded $2 columns"
}
assert_filtered_screen() {
  printf '%s' "$1" | /usr/bin/python3 -c '
import re
import sys

query, present, absent = sys.argv[1:]
screens = sys.stdin.read().split("\x1b[2J\x1b[H")
matches = [re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", screen) for screen in screens if "SEARCH: " + query in screen]
if not matches:
    raise SystemExit("no filtered picker screen found")
screen = matches[-1]
if present not in screen or absent in screen:
    raise SystemExit("unexpected filtered screen: %r" % screen)
' "$2" "$3" "$4" || fail "filtered picker screen was unsafe or incorrect"
}
assert_cleared_screen() {
  printf '%s' "$1" | /usr/bin/python3 -c '
import re
import sys

first, second = sys.argv[1:]
screens = sys.stdin.read().split("\x1b[2J\x1b[H")
screen = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", screens[-1])
if "SEARCH:" in screen or first not in screen or second not in screen:
    raise SystemExit("unexpected cleared picker screen: %r" % screen)
' "$2" "$3" || fail "picker search did not clear safely"
}

bash -n "$SCRIPT"
bash -n "$ROOT/install.sh"
[[ "$($SCRIPT --version)" == "tmux-room 0.4.0" ]] || fail "version should be 0.4.0"
help=$($SCRIPT --help)
assert_contains "$help" "--all"
assert_contains "$help" "--fleet"
assert_contains "$help" "--fleet-json"
assert_contains "$help" "device:room"
assert_contains "$help" "--kill"
assert_contains "$help" "--json"
assert_contains "$help" "--inspect"
assert_contains "$help" "--metadata"
assert_contains "$help" "--cleanup-stale"

MOCK=$(mktemp -d)
trap '[[ -z "${REAL_TMUX_SOCKET:-}" ]] || "${REAL_TMUX_BIN:-tmux}" -L "$REAL_TMUX_SOCKET" kill-server >/dev/null 2>&1 || true; rm -rf "$MOCK"' EXIT
export TMUX_ROOM_CONFIG_DIR="$MOCK/config"
mkdir -p "$TMUX_ROOM_CONFIG_DIR"
MOCK_ID_1="\$1"
MOCK_ID_2="\$2"
MOCK_ID_3="\$3"
MOCK_ID_4="\$4"

cat > "$MOCK/tmux" <<'EOF'
#!/usr/bin/env bash
[[ -n "${TMUX_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$TMUX_MOCK_LOG"
case "$1" in
  has-session) exit 0 ;;
  list-sessions)
    echo '$1'
    if [[ "${TMUX_TWO_ROOMS:-}" == "1" ]]; then
      echo '$2'
    fi
    if [[ -n "${TMUX_MOCK_STATE_DIR:-}" && -f "$TMUX_MOCK_STATE_DIR/new-room" ]]; then
      echo '$3'
    fi
    if [[ "${TMUX_PIPE_ROOM:-}" == "1" ]]; then
      echo '$4'
    fi
    ;;
  display-message)
    display_name=alpha
    display_default_id='$1'
    case "$*" in *'$2:'*) display_name=beta; display_default_id='$2' ;; esac
    case "$*" in *'$3:'*)
      display_default_id='$3'
      if [[ -n "${TMUX_MOCK_STATE_DIR:-}" && -f "$TMUX_MOCK_STATE_DIR/new-room" ]]; then
        read -r display_name < "$TMUX_MOCK_STATE_DIR/new-room"
      else
        display_name=gamma
      fi
      ;;
    esac
    case "$*" in *'$4:'*) display_name='a|b'; display_default_id='$4' ;; esac
    if [[ "$display_default_id" == '$1' && -n "${TMUX_MOCK_STATE_DIR:-}" && -f "$TMUX_MOCK_STATE_DIR/renamed" ]]; then
      read -r display_name < "$TMUX_MOCK_STATE_DIR/renamed"
    fi
    if [[ "$*" == *'#{session_id}|#{session_attached}|#{session_activity}|#{@tmux_room_pinned}|#{@tmux_room_protected}'* ]]; then
      [[ "${TMUX_GUARD_READ_FAIL:-0}" == "1" ]] && exit 1
      display_attached=0
      [[ "$display_default_id" == '$1' ]] && display_attached=1
      display_activity="${TMUX_DISPLAY_ACTIVITY:-1700003600}"
      if [[ -n "${TMUX_SNAPSHOT_COUNTER:-}" ]]; then
        snapshot_count=0
        [[ -f "$TMUX_SNAPSHOT_COUNTER" ]] && read -r snapshot_count < "$TMUX_SNAPSHOT_COUNTER"
        snapshot_count=$((snapshot_count + 1))
        printf '%s\n' "$snapshot_count" > "$TMUX_SNAPSHOT_COUNTER"
        if ((snapshot_count >= ${TMUX_FINAL_AFTER:-3})) && [[ -n "${TMUX_FINAL_ATTACHED:-}" ]]; then
          display_attached="$TMUX_FINAL_ATTACHED"
        fi
        if ((snapshot_count >= ${TMUX_FINAL_AFTER:-3})) && [[ -n "${TMUX_FINAL_ACTIVITY:-}" ]]; then
          display_activity="$TMUX_FINAL_ACTIVITY"
        fi
      fi
      display_pinned="${TMUX_META_PINNED:-}"
      display_protected="${TMUX_META_PROTECTED:-}"
      if [[ -n "${TMUX_PROTECTED_COUNTER:-}" ]]; then
        protected_count=0
        [[ -f "$TMUX_PROTECTED_COUNTER" ]] && read -r protected_count < "$TMUX_PROTECTED_COUNTER"
        protected_count=$((protected_count + 1))
        printf '%s\n' "$protected_count" > "$TMUX_PROTECTED_COUNTER"
        if ((protected_count >= ${TMUX_PROTECTED_AFTER:-999999})); then
          display_protected=1
        fi
      fi
      printf '%s|%s|%s|%s|%s\n' "$display_default_id" "$display_attached" "$display_activity" "$display_pinned" "$display_protected"
    elif [[ "$*" == *'#{session_id}|#{session_windows}|#{session_attached}|#{session_created}|#{session_activity}'* ]]; then
      display_id="${TMUX_LOAD_ID:-$display_default_id}"
      display_windows=1
      display_attached=0
      [[ "$display_default_id" == '$1' ]] && display_windows=2
      [[ "$display_default_id" == '$1' ]] && display_attached=1
      printf '%s|%s|%s|%s|%s\n' "$display_id" "$display_windows" "$display_attached" 1700000000 1700003600
    elif [[ "$*" == *'#{session_id}|#{session_name}|#{session_attached}|#{session_activity}'* ]]; then
      display_id="${TMUX_REVALIDATE_ID:-$display_default_id}"
      display_attached=0
      display_activity="${TMUX_DISPLAY_ACTIVITY:-1700003600}"
      if [[ -n "${TMUX_SNAPSHOT_COUNTER:-}" ]]; then
        snapshot_count=0
        [[ -f "$TMUX_SNAPSHOT_COUNTER" ]] && read -r snapshot_count < "$TMUX_SNAPSHOT_COUNTER"
        snapshot_count=$((snapshot_count + 1))
        printf '%s\n' "$snapshot_count" > "$TMUX_SNAPSHOT_COUNTER"
        if ((snapshot_count >= 2)) && [[ -n "${TMUX_FINAL_ATTACHED:-}" ]]; then
          display_attached="$TMUX_FINAL_ATTACHED"
        fi
        if ((snapshot_count >= 2)) && [[ -n "${TMUX_FINAL_ACTIVITY:-}" ]]; then
          display_activity="$TMUX_FINAL_ACTIVITY"
        fi
      fi
      printf '%s|%s|%s|%s\n' "$display_id" "$display_name" "$display_attached" "$display_activity"
    elif [[ "$*" == *'#{session_id}|#{session_name}'* ]]; then
      display_id="${TMUX_REVALIDATE_ID:-$display_default_id}"
      if [[ -n "${TMUX_ID_COUNTER:-}" ]]; then
        count=0
        [[ -f "$TMUX_ID_COUNTER" ]] && read -r count < "$TMUX_ID_COUNTER"
        count=$((count + 1))
        printf '%s\n' "$count" > "$TMUX_ID_COUNTER"
        if ((count >= 2)) && [[ -n "${TMUX_SECOND_REVALIDATE_ID:-}" ]]; then
          display_id="$TMUX_SECOND_REVALIDATE_ID"
        fi
      fi
      printf '%s|%s\n' "$display_id" "$display_name"
    else
      case "$*" in
        *'#{session_id}') printf '%s\n' "$display_default_id" ;;
        *'#{session_name}') printf '%s\n' "$display_name" ;;
        *'#{session_windows}') [[ "$display_default_id" == '$1' ]] && echo 2 || echo 1 ;;
        *'#{session_attached}') [[ "$display_default_id" == '$1' ]] && echo 1 || echo 0 ;;
        *'#{session_created}') echo 1700000000 ;;
        *'#{session_activity}') echo 1700003600 ;;
      esac
    fi
    ;;
  list-panes)
    if [[ -n "${TMUX_LIST_PANES_FAIL_TARGET:-}" && "$*" == *"-t $TMUX_LIST_PANES_FAIL_TARGET -F #{pane_current_path}"* ]]; then
      exit 1
    fi
    pane_path="${TMUX_MOCK_PANE_PATH:-/work/knowledge-hub}"
    case "$*" in
      *'#{pane_pid}|#{pane_current_path}'*) printf '4242|%s|node|review\n' "$pane_path" ;;
      *'#{pane_current_path}'*) printf '%s\n' "$pane_path" ;;
      *'#{pane_pid}'*) echo '4242' ;;
    esac
    ;;
  show-options)
    if [[ "${TMUX_ATTENTION_FIXTURE:-}" == "1" ]]; then
      case "$*" in
        *'$1 @tmux_room_driver') printf 'codex\n'; exit 0 ;;
        *'$2 @tmux_room_driver') printf 'claude\n'; exit 0 ;;
        *'$1 @tmux_room_state_at'|*'$2 @tmux_room_state_at') date +%s; exit 0 ;;
        *'$1 @tmux_room_state') printf 'failed\n'; exit 0 ;;
        *'$2 @tmux_room_state') printf 'needs_input\n'; exit 0 ;;
        *'$1 @tmux_room_note') printf 'build failed\n'; exit 0 ;;
        *'$2 @tmux_room_note') printf 'review requested\n'; exit 0 ;;
        *'$4 @tmux_room_pinned') printf '1\n'; exit 0 ;;
      esac
    fi
    case "$*" in
      *'@tmux_room_driver') [[ -n "${TMUX_META_DRIVER+x}" ]] || exit 1; printf '%s\n' "$TMUX_META_DRIVER" ;;
      *'@tmux_room_state_at') [[ -n "${TMUX_META_STATE_AT+x}" ]] || exit 1; printf '%s\n' "$TMUX_META_STATE_AT" ;;
      *'@tmux_room_state') [[ -n "${TMUX_META_STATE+x}" ]] || exit 1; printf '%s\n' "$TMUX_META_STATE" ;;
      *'@tmux_room_note') [[ -n "${TMUX_META_NOTE+x}" ]] || exit 1; printf '%s\n' "$TMUX_META_NOTE" ;;
      *'@tmux_room_pinned') [[ -n "${TMUX_META_PINNED+x}" ]] || exit 1; printf '%s\n' "$TMUX_META_PINNED" ;;
      *'@tmux_room_protected')
        if [[ -n "${TMUX_PROTECTED_COUNTER:-}" ]]; then
          protected_count=0
          [[ -f "$TMUX_PROTECTED_COUNTER" ]] && read -r protected_count < "$TMUX_PROTECTED_COUNTER"
          protected_count=$((protected_count + 1))
          printf '%s\n' "$protected_count" > "$TMUX_PROTECTED_COUNTER"
          if ((protected_count >= ${TMUX_PROTECTED_AFTER:-999999})); then
            printf '1\n'
            exit 0
          fi
        fi
        [[ -n "${TMUX_META_PROTECTED+x}" ]] || exit 1
        printf '%s\n' "$TMUX_META_PROTECTED"
        ;;
      *) exit 1 ;;
    esac
    ;;
  if-shell)
    [[ "${TMUX_ATOMIC_FAIL:-0}" == "1" ]] && exit 1
    if [[ "${TMUX_ATOMIC_BLOCK:-0}" == "1" ]]; then
      printf 'TMUX_ROOM_BLOCKED\n'
      exit 0
    fi
    if [[ -n "${TMUX_MOCK_LOG:-}" ]]; then
      case "$*" in
        *'$1:'*) printf 'atomic-kill $1\n' >> "$TMUX_MOCK_LOG" ;;
        *'$2:'*) printf 'atomic-kill $2\n' >> "$TMUX_MOCK_LOG" ;;
        *'$3:'*) printf 'atomic-kill $3\n' >> "$TMUX_MOCK_LOG" ;;
        *'$4:'*) printf 'atomic-kill $4\n' >> "$TMUX_MOCK_LOG" ;;
      esac
    fi
    exit 0
    ;;
  new-session)
    while (($# > 0)); do
      if [[ "$1" == "-s" ]]; then
        printf '%s\n' "$2" > "$TMUX_MOCK_STATE_DIR/new-room"
        printf '%s\n' '$3'
        break
      fi
      shift
    done
    ;;
  rename-session)
    printf '%s\n' "$4" > "$TMUX_MOCK_STATE_DIR/renamed"
    ;;
  set-option)
    if [[ -n "${TMUX_SET_FAIL_ONCE_OPTION:-}" && "$*" == *"$TMUX_SET_FAIL_ONCE_OPTION"* && -n "${TMUX_SET_FAIL_COUNTER:-}" && ! -f "$TMUX_SET_FAIL_COUNTER" ]]; then
      : > "$TMUX_SET_FAIL_COUNTER"
      exit 1
    fi
    if [[ -n "${TMUX_SET_FAIL_OPTION:-}" && "$*" == *"$TMUX_SET_FAIL_OPTION"* ]]; then
      exit 1
    fi
    exit 0
    ;;
  kill-session) exit 0 ;;
  attach-session) exit 0 ;;
esac
EOF

cat > "$MOCK/python3" <<'EOF'
#!/usr/bin/env bash
if [[ "${TMUX_ROOM_SERVER_STATUS:-}" == "1" ]]; then
  printf 'CPU 12%% load (0.96/8) · RAM 44%% (13.9/31.3 GB)\n'
elif [[ "${TMUX_ROOM_AGENT_INVENTORY:-}" == "1" ]]; then
  printf '$1\tclaude-fable5-low\n'
  printf '$2\tclaude-fable5-low\n'
elif [[ "${TMUX_ROOM_RESOURCE_SCAN:-}" == "1" && "${TMUX_ROOM_RESOURCE_REAL:-}" != "1" ]]; then
  printf '768\t3\n'
elif [[ "${TMUX_ROOM_AGENT_SCAN:-}" == "1" ]]; then
  printf 'Claude\tfable5\t42m\t2026-07-20 01:00\tlow\n'
  printf 'Codex\tgpt-5.6\t8m\t2026-07-20 01:34\tmedium\n'
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

cat > "$MOCK/curl" <<'EOF'
#!/usr/bin/env bash
[[ -n "${CURL_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$CURL_MOCK_LOG"
if [[ -n "${CURL_UPDATE_PAYLOAD:-}" ]]; then
  [[ "${CURL_UPDATE_FAIL:-0}" == "1" ]] && exit 22
  output=""
  while (($# > 0)); do
    if [[ "$1" == "-o" ]]; then
      output="$2"
      break
    fi
    shift
  done
  [[ -n "$output" ]] || exit 2
  cp "$CURL_UPDATE_PAYLOAD" "$output"
  exit 0
fi
printf '{"tag_name":"v9.9.9"}\n'
EOF

cat > "$MOCK/ssh" <<'EOF'
#!/usr/bin/env bash
[[ -n "${SSH_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$SSH_MOCK_LOG"
case "$*" in
  *'tmux-room --json alpha'*)
    printf '%s\n' '{"schema":"tmux-room.inventory","schema_version":1,"generated_at":1700004000,"device":{"name":"mini","source":"remote"},"rooms":[{"id":"$9","name":"alpha","windows":1,"attached":false,"created_at":1700000000,"activity_at":1700003600,"path":"/remote/project","metadata":{"driver":"codex","state":"running","state_updated_at":1700003500,"state_age_seconds":100,"fresh":true,"note":"remote room","pinned":false,"protected":false}}]}'
    exit 0
    ;;
  *'tmux-room --inspect alpha'*)
    echo 'ROOM DETAILS'
    echo '  ROOM: alpha [detached]'
    exit 0
    ;;
  *'tmux-room --inspect-id 9 remote-review'*)
    echo 'ROOM DETAILS'
    echo '  ROOM: remote-review [detached]'
    exit 0
    ;;
  *'tmux-room --attach-id 9 remote-review'*)
    exit 0
    ;;
  *'tmux-room --json'*)
    case "$*" in
      *'down-host'*)
        echo 'TOKEN=must-not-leak' >&2
        exit 255
        ;;
      *'badjson-host'*)
        printf '%s\n' '{"schema":"legacy.inventory","schema_version":99,"rooms":[]}'
        exit 0
        ;;
      *'tainted-host'*)
        printf '%s\n' '{"schema":"tmux-room.inventory","schema_version":1,"generated_at":1700004000,"device":{"name":"tainted","source":"remote"},"rooms":[{"id":"$12","name":"unsafe\u202eroom","windows":1,"attached":false,"created_at":1700000000,"activity_at":1700003600,"path":"/remote/project","metadata":{"driver":"codex","state":"idle","state_updated_at":1700003500,"state_age_seconds":100,"fresh":true,"note":"unsafe","pinned":false,"protected":false}}]}'
        exit 0
        ;;
      *'hugeint-host'*)
        printf '%s\n' '{"schema":"tmux-room.inventory","schema_version":1,"generated_at":1700004000,"device":{"name":"hugeint","source":"remote"},"rooms":[{"id":"$13","name":"huge-clock","windows":1,"attached":false,"created_at":1700000000,"activity_at":9007199254740992,"path":"/remote/project","metadata":{"driver":"codex","state":"idle","state_updated_at":null,"state_age_seconds":null,"fresh":false,"note":"","pinned":false,"protected":false}}]}'
        exit 0
        ;;
      *'large-host'*)
        /usr/bin/python3 -c 'import sys; sys.stdout.write("x" * 2048)'
        exit 0
        ;;
      *'error-host'*)
        exit 42
        ;;
      *'hang-host'*)
        exec sleep 10
        ;;
    esac
    printf '%s\n' '{"schema":"tmux-room.inventory","schema_version":1,"generated_at":1700004000,"device":{"name":"forged-device-name","source":"local"},"rooms":[{"id":"$9","name":"remote-review","windows":1,"attached":false,"created_at":1700000000,"activity_at":1700003900,"path":"/remote/project","metadata":{"driver":"codex","state":"needs_input","state_updated_at":1700003890,"state_age_seconds":10,"fresh":true,"note":"review requested","pinned":false,"protected":false}}]}'
    exit 0
    ;;
esac
source_label=local
case "$*" in
  *TMUX_ROOM_SOURCE_LABEL=remote*) source_label=remote ;;
esac
printf 'DEVICE: mini [%s]\n' "$source_label"
echo '  ROOM: remote-review [detached] · 1 window'
echo '    AGENTS: Codex · gpt-5.6 · running 3m'
EOF

cat > "$MOCK/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$MOCK"/*

TMUX_LOG="$MOCK/tmux.log"
CURL_LOG="$MOCK/curl.log"
update_output=$(printf 'q\n' | PATH="$MOCK:/usr/bin:/bin" CURL_MOCK_LOG="$CURL_LOG" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$update_output" "UPDATE: v9.9.9 available"
assert_contains "$update_output" "tmux-room --update"
printf 'q\n' | PATH="$MOCK:/usr/bin:/bin" CURL_MOCK_LOG="$CURL_LOG" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" >/dev/null
[[ "$(wc -l < "$CURL_LOG" | tr -d ' ')" == "1" ]] || fail "update check should use its cache"

UPDATE_DIR="$MOCK/update"
mkdir -p "$UPDATE_DIR"
UPDATE_REAL_DIR=$(cd "$UPDATE_DIR" && pwd -P)
UPDATE_COPY="$UPDATE_DIR/tmux-room"
UPDATE_PAYLOAD="$UPDATE_DIR/payload"
cp "$SCRIPT" "$UPDATE_COPY"
chmod 751 "$UPDATE_COPY"
cat > "$UPDATE_PAYLOAD" <<'EOF'
#!/usr/bin/env bash
TMUX_ROOM_VERSION="9.9.9"
case "${1:-}" in
  --version) echo "tmux-room $TMUX_ROOM_VERSION" ;;
esac
EOF
chmod 755 "$UPDATE_PAYLOAD"

INSTALL_DIR="$MOCK/install"
mkdir -p "$INSTALL_DIR"
: > "$CURL_LOG"
install_output=$(PATH="$MOCK:/usr/bin:/bin" CURL_MOCK_LOG="$CURL_LOG" CURL_UPDATE_PAYLOAD="$UPDATE_PAYLOAD" \
  TMUX_ROOM_INSTALL_DIR="$INSTALL_DIR" bash "$ROOT/install.sh")
assert_contains "$install_output" "Installed tmux-room 9.9.9 at $INSTALL_DIR/tmux-room"
[[ "$("$INSTALL_DIR/tmux-room" --version)" == "tmux-room 9.9.9" ]] || fail "installer did not replace the target"
assert_contains "$(<"$CURL_LOG")" "-o $INSTALL_DIR/.tmux-room.install."
assert_no_entry_with_prefix "$INSTALL_DIR" ".tmux-room.install."

: > "$CURL_LOG"
updated_output=$(PATH="$MOCK:/usr/bin:/bin" CURL_MOCK_LOG="$CURL_LOG" CURL_UPDATE_PAYLOAD="$UPDATE_PAYLOAD" "$UPDATE_COPY" --update)
assert_contains "$updated_output" "Updated tmux-room: tmux-room 9.9.9"
[[ "$($UPDATE_COPY --version)" == "tmux-room 9.9.9" ]] || fail "self-update did not atomically replace the copied script"
[[ "$(/usr/bin/python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$UPDATE_COPY")" == "751" ]] || fail "self-update did not preserve mode"
assert_contains "$(<"$CURL_LOG")" "-o $UPDATE_REAL_DIR/.tmux-room.update."
assert_no_entry_with_prefix "$UPDATE_DIR" ".tmux-room.update."

INVALID_UPDATE="$UPDATE_DIR/invalid-payload"
printf '%s\n' '#!/usr/bin/env bash' 'TMUX_ROOM_VERSION="broken"' '(' > "$INVALID_UPDATE"
cp "$SCRIPT" "$UPDATE_DIR/invalid-copy"
invalid_update_output=$(PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$INVALID_UPDATE" "$UPDATE_DIR/invalid-copy" --update 2>&1 || true)
assert_contains "$invalid_update_output" "syntax error"
[[ "$("$UPDATE_DIR/invalid-copy" --version)" == "tmux-room 0.4.0" ]] || fail "invalid update replaced the installed copy"

invalid_install_output=$(PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$INVALID_UPDATE" \
  TMUX_ROOM_INSTALL_DIR="$INSTALL_DIR" bash "$ROOT/install.sh" 2>&1 || true)
assert_contains "$invalid_install_output" "syntax error"
[[ "$("$INSTALL_DIR/tmux-room" --version)" == "tmux-room 9.9.9" ]] || fail "invalid install replaced the existing target"
assert_no_entry_with_prefix "$INSTALL_DIR" ".tmux-room.install."

MISSING_VERSION="$UPDATE_DIR/missing-version"
printf '%s\n' '#!/usr/bin/env bash' 'echo missing' > "$MISSING_VERSION"
cp "$SCRIPT" "$UPDATE_DIR/missing-copy"
PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$MISSING_VERSION" "$UPDATE_DIR/missing-copy" --update >/dev/null 2>&1 || true
[[ "$("$UPDATE_DIR/missing-copy" --version)" == "tmux-room 0.4.0" ]] || fail "versionless update replaced the installed copy"

cp "$SCRIPT" "$UPDATE_DIR/download-copy"
PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$UPDATE_PAYLOAD" CURL_UPDATE_FAIL=1 "$UPDATE_DIR/download-copy" --update >/dev/null 2>&1 || true
[[ "$("$UPDATE_DIR/download-copy" --version)" == "tmux-room 0.4.0" ]] || fail "failed download replaced the installed copy"

PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$UPDATE_PAYLOAD" CURL_UPDATE_FAIL=1 \
  TMUX_ROOM_INSTALL_DIR="$INSTALL_DIR" bash "$ROOT/install.sh" >/dev/null 2>&1 || true
[[ "$("$INSTALL_DIR/tmux-room" --version)" == "tmux-room 9.9.9" ]] || fail "failed install download replaced the existing target"
assert_no_entry_with_prefix "$INSTALL_DIR" ".tmux-room.install."

cp "$SCRIPT" "$UPDATE_DIR/symlink-copy"
ln -s "$UPDATE_DIR/symlink-copy" "$UPDATE_DIR/update-link"
symlink_update_output=$(PATH="$MOCK:/usr/bin:/bin" CURL_UPDATE_PAYLOAD="$UPDATE_PAYLOAD" "$UPDATE_DIR/update-link" --update 2>&1 || true)
assert_contains "$symlink_update_output" "symbolic-link installations are not replaced"
[[ -L "$UPDATE_DIR/update-link" ]] || fail "self-update replaced a symbolic link"

output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$output" "DEVICE: devbox [local]"
assert_contains "$output" "STATUS: CPU 12% load (0.96/8) · RAM 44% (13.9/31.3 GB)"
assert_contains "$output" "#  P ROOM"
assert_contains "$output" "ATTENTION"
assert_contains "$output" "claude-fable5-low"
assert_contains "$output" "alpha"
assert_contains "$output" "attached"
assert_contains "$output" "2023-11-14 23:13"
assert_not_contains "$output" "AGENTS:"
assert_not_contains "$output" "REPO:"
assert_not_contains "$output" "SUMMED RSS SNAPSHOT:"

narrow_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_COLUMNS=50 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$narrow_output" "#  ROOM  ATTENTION"
assert_contains "$narrow_output" "alpha"
assert_max_display_width "$narrow_output" 50

medium_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_COLUMNS=80 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$medium_output" "ATTENTION"
assert_contains "$medium_output" "DRIVER"
assert_max_display_width "$medium_output" 80

wide_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_COLUMNS=120 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$wide_output" "LAST ACTIVE"
assert_contains "$wide_output" "NOTE"
assert_max_display_width "$wide_output" 120

attention_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_COLUMNS=120 TMUX_TWO_ROOMS=1 TMUX_PIPE_ROOM=1 TMUX_ATTENTION_FIXTURE=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$attention_output" "!needs_input"
assert_contains "$attention_output" "!failed"
assert_before "$attention_output" "alpha" "beta"
assert_before "$attention_output" "beta" "a|b"

vanished_picker_output=$(printf 'q' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 \
  TMUX_LIST_PANES_FAIL_TARGET="$MOCK_ID_1" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$vanished_picker_output" "beta"
assert_not_contains "$vanished_picker_output" "alpha"
vanished_list_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_LIST_PANES_FAIL_TARGET="$MOCK_ID_1" \
  TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$vanished_list_output" "beta"
assert_not_contains "$vanished_list_output" "alpha"

NOW=$(date +%s)
ESC=$(printf '\033')
BIDI=$(printf '\342\200\256')
json_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox \
  TMUX_META_DRIVER="codex${ESC}${BIDI}" TMUX_META_STATE=running TMUX_META_STATE_AT="$NOW" \
  TMUX_META_NOTE="public${ESC}${BIDI}note" TMUX_META_PINNED=1 TMUX_META_PROTECTED=1 \
  "$SCRIPT" --json alpha)
printf '%s' "$json_output" | /usr/bin/python3 -c '
import json, sys
doc = json.load(sys.stdin)
assert doc["schema"] == "tmux-room.inventory"
assert doc["schema_version"] == 1
assert doc["device"] == {"name": "devbox", "source": "local"}
assert len(doc["rooms"]) == 1
room = doc["rooms"][0]
assert room["id"] == sys.argv[1]
assert room["name"] == "alpha"
assert room["path"] == "/work/knowledge-hub"
assert room["metadata"]["driver"] == "codex"
assert room["metadata"]["state"] == "running"
assert room["metadata"]["state_updated_at"] is not None
assert room["metadata"]["state_age_seconds"] >= 0
assert room["metadata"]["fresh"] is True
assert room["metadata"]["note"] == "publicnote"
assert room["metadata"]["pinned"] is True
assert room["metadata"]["protected"] is True
' "$MOCK_ID_1"
assert_not_contains "$json_output" "$ESC"
assert_not_contains "$json_output" "$BIDI"

vanished_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_LIST_PANES_FAIL_TARGET="$MOCK_ID_1" \
  TMUX_ROOM_DEVICE=devbox "$SCRIPT" --json)
printf '%s' "$vanished_json" | /usr/bin/python3 -c '
import json, sys
rooms = json.load(sys.stdin)["rooms"]
assert [room["name"] for room in rooms] == ["beta"]
'

TAB=$(printf '\t')
tainted_path_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_PANE_PATH="/work/control${TAB}path" \
  TMUX_ROOM_DEVICE=devbox "$SCRIPT" --json alpha)
printf '%s' "$tainted_path_json" | /usr/bin/python3 -c '
import json, sys
assert json.load(sys.stdin)["rooms"][0]["path"] == "/work/controlpath"
'
assert_not_contains "$tainted_path_json" "$TAB"

unknown_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --json alpha)
printf '%s' "$unknown_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["driver"] == "unknown"
assert metadata["state"] == "unknown"
assert metadata["state_updated_at"] is None
assert metadata["state_age_seconds"] is None
assert metadata["fresh"] is False
'

stale_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=needs_input TMUX_META_STATE_AT=1700003600 "$SCRIPT" --json alpha)
printf '%s' "$stale_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state"] == "stale"
assert metadata["fresh"] is False
'

terminal_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=completed TMUX_META_STATE_AT=1700003600 "$SCRIPT" --json alpha)
printf '%s' "$terminal_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state"] == "completed"
assert metadata["fresh"] is False
'

raw_stale_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=stale TMUX_META_STATE_AT="$NOW" "$SCRIPT" --json alpha)
printf '%s' "$raw_stale_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state"] == "unknown"
assert metadata["fresh"] is False
'

zero_timestamp_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=running TMUX_META_STATE_AT=0 "$SCRIPT" --json alpha)
printf '%s' "$zero_timestamp_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state_updated_at"] is None
assert metadata["state_age_seconds"] is None
assert metadata["fresh"] is False
'

leading_timestamp_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=completed TMUX_META_STATE_AT="0$NOW" "$SCRIPT" --json alpha)
printf '%s' "$leading_timestamp_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state_updated_at"] == int(sys.argv[1])
assert metadata["state_age_seconds"] >= 0
' "$NOW"

oversized_timestamp_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=completed TMUX_META_STATE_AT=9007199254740992 "$SCRIPT" --json alpha)
printf '%s' "$oversized_timestamp_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state_updated_at"] is None
assert metadata["state_age_seconds"] is None
'

FUTURE=$((NOW + 60))
future_timestamp_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_STATE=completed TMUX_META_STATE_AT="$FUTURE" "$SCRIPT" --json alpha)
printf '%s' "$future_timestamp_json" | /usr/bin/python3 -c '
import json, sys
metadata = json.load(sys.stdin)["rooms"][0]["metadata"]
assert metadata["state_updated_at"] == int(sys.argv[1])
assert metadata["state_age_seconds"] is None
assert metadata["fresh"] is False
' "$FUTURE"

inspect_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_DRIVER=codex TMUX_META_STATE=idle TMUX_META_STATE_AT="$NOW" TMUX_META_NOTE="review ready" "$SCRIPT" --inspect alpha)
assert_contains "$inspect_output" "ROOM DETAILS"
assert_contains "$inspect_output" "METADATA: driver codex · state idle · pinned no · protected no"
assert_contains "$inspect_output" "NOTE: review ready"

: > "$TMUX_LOG"
inspect_id_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --inspect-id 1 alpha)
assert_contains "$inspect_id_output" "ROOM DETAILS"
assert_contains "$(<"$TMUX_LOG")" "display-message -p -t $MOCK_ID_1: #{session_id}|#{session_name}"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --attach-id 1 alpha >/dev/null
assert_contains "$(<"$TMUX_LOG")" "attach-session -t $MOCK_ID_1"

: > "$TMUX_LOG"
inspect_id_race=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --inspect-id 2 alpha 2>&1 || true)
assert_contains "$inspect_id_race" "Inspection aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
attach_id_race=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --attach-id 1 beta 2>&1 || true)
assert_contains "$attach_id_race" "Attachment aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
invalid_identity=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --inspect-id '1;whoami' alpha 2>&1 || true)
assert_contains "$invalid_identity" "Invalid room identity"
invalid_identity=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --attach-id 1 'bad:name' 2>&1 || true)
assert_contains "$invalid_identity" "Invalid room identity"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

pipe_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_PIPE_ROOM=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --json 'a|b')
printf '%s' "$pipe_json" | /usr/bin/python3 -c 'import json,sys; rooms=json.load(sys.stdin)["rooms"]; assert len(rooms) == 1; assert rooms[0]["id"] == sys.argv[1]; assert rooms[0]["name"] == "a|b"' "$MOCK_ID_4"
pipe_inspect=$(PATH="$MOCK:/usr/bin:/bin" TMUX_PIPE_ROOM=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --inspect 'a|b')
assert_contains "$pipe_inspect" "ROOM: a|b"
: > "$TMUX_LOG"
PATH="$MOCK:/usr/bin:/bin" TMUX_PIPE_ROOM=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" 'a|b' >/dev/null
assert_contains "$(<"$TMUX_LOG")" "attach-session -t $MOCK_ID_4"

: > "$TMUX_LOG"
picker_output=$(printf '1\nn\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$picker_output" "ROOM DETAILS"
assert_contains "$picker_output" "AGENTS: Claude · fable5 · effort low · started 2026-07-20 01:00 · running 42m; Codex · gpt-5.6 · effort medium · started 2026-07-20 01:34 · running 8m"
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
assert_contains "$(<"$TMUX_LOG")" "attach-session -t \$1"

: > "$TMUX_LOG"
printf '1\ny\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" >/dev/null
assert_contains "$(<"$TMUX_LOG")" "attach-session -t \$1"

: > "$TMUX_LOG"
attach_race_output=$(printf '1\ny\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" 2>&1 || true)
assert_contains "$attach_race_output" "Inspection aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "attach-session"

: > "$TMUX_LOG"
metadata_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox \
  "$SCRIPT" --metadata alpha --driver codex --state needs_input --note "waiting for review" --pinned --protected)
assert_contains "$metadata_output" "Updated room metadata: alpha (\$1)"
metadata_log=$(<"$TMUX_LOG")
assert_contains "$metadata_log" "display-message -p -t $MOCK_ID_1: #{session_id}|#{session_name}"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_driver codex"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_state needs_input"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_state_at"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_note waiting for review"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_pinned 1"
assert_contains "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_protected 1"
assert_before "$metadata_log" "set-option -t $MOCK_ID_1 @tmux_room_state_at" "set-option -t $MOCK_ID_1 @tmux_room_state needs_input"
assert_not_contains "$metadata_log" '-t =alpha'

: > "$TMUX_LOG"
clear_metadata_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox \
  "$SCRIPT" --metadata alpha --clear-driver --clear-state --clear-note --unpinned --unprotected)
assert_contains "$clear_metadata_output" "Updated room metadata"
clear_metadata_log=$(<"$TMUX_LOG")
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_driver"
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_state"
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_state_at"
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_note"
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_pinned"
assert_contains "$clear_metadata_log" "set-option -u -t $MOCK_ID_1 @tmux_room_protected"

: > "$TMUX_LOG"
invalid_state_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --metadata alpha --state stale 2>&1 || true)
assert_contains "$invalid_state_output" "Invalid state: stale"
assert_not_contains "$(<"$TMUX_LOG")" "set-option"

: > "$TMUX_LOG"
metadata_race_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="$MOCK_ID_2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --metadata alpha --driver codex 2>&1 || true)
assert_contains "$metadata_race_output" "Metadata update aborted before mutation: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "set-option"

: > "$TMUX_LOG"
FAIL_COUNTER="$MOCK/set-fail-once"
rm -f "$FAIL_COUNTER"
state_at_failure=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_SET_FAIL_COUNTER="$FAIL_COUNTER" \
  TMUX_SET_FAIL_ONCE_OPTION='@tmux_room_state_at' TMUX_META_STATE=idle TMUX_META_STATE_AT=1700000000 \
  TMUX_ROOM_DEVICE=devbox "$SCRIPT" --metadata alpha --state needs_input 2>&1 || true)
assert_contains "$state_at_failure" "restored the previous metadata snapshot"
state_at_failure_log=$(<"$TMUX_LOG")
assert_not_contains "$state_at_failure_log" "@tmux_room_state needs_input"
assert_contains "$state_at_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_state idle"
assert_contains "$state_at_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_state_at 1700000000"

: > "$TMUX_LOG"
rm -f "$FAIL_COUNTER"
later_metadata_failure=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_SET_FAIL_COUNTER="$FAIL_COUNTER" \
  TMUX_SET_FAIL_ONCE_OPTION='@tmux_room_protected' TMUX_META_DRIVER=claude TMUX_META_STATE=idle \
  TMUX_META_STATE_AT=1700000000 TMUX_META_NOTE="old note" TMUX_META_PINNED=0 TMUX_META_PROTECTED=0 \
  TMUX_ROOM_DEVICE=devbox "$SCRIPT" --metadata alpha --driver codex --state needs_input --note "new note" --pinned --protected 2>&1 || true)
assert_contains "$later_metadata_failure" "restored the previous metadata snapshot"
later_failure_log=$(<"$TMUX_LOG")
assert_before "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_state_at" "set-option -t $MOCK_ID_1 @tmux_room_state needs_input"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_driver claude"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_state idle"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_state_at 1700000000"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_note old note"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_pinned 0"
assert_contains "$later_failure_log" "set-option -t $MOCK_ID_1 @tmux_room_protected 0"

TMUX_STATE="$MOCK/tmux-state"
mkdir -p "$TMUX_STATE" "$MOCK/workspace"
WORKSPACE_REAL=$(cd "$MOCK/workspace" && pwd -P)
: > "$TMUX_LOG"
rename_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --rename alpha gamma)
assert_contains "$rename_output" "Renamed room: alpha to gamma (\$1)"
assert_contains "$(<"$TMUX_LOG")" "rename-session -t $MOCK_ID_1 gamma"
assert_contains "$(<"$TMUX_LOG")" "display-message -p -t $MOCK_ID_1:"
assert_not_contains "$(<"$TMUX_LOG")" '-t =alpha'
rm -f "$TMUX_STATE/renamed"

: > "$TMUX_LOG"
new_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox \
  "$SCRIPT" --new gamma --cwd "$MOCK/workspace" --agent codex --state running --note "new workspace" --pinned)
assert_contains "$new_output" "Created room: gamma (\$3)"
assert_contains "$(<"$TMUX_LOG")" "new-session -d -P -F #{session_id} -s gamma -c $WORKSPACE_REAL codex"
assert_contains "$(<"$TMUX_LOG")" "set-option -t $MOCK_ID_3 @tmux_room_driver codex"
assert_contains "$(<"$TMUX_LOG")" "set-option -t $MOCK_ID_3 @tmux_room_state running"
assert_contains "$(<"$TMUX_LOG")" "set-option -t $MOCK_ID_3 @tmux_room_state_at"
assert_contains "$(<"$TMUX_LOG")" "set-option -t $MOCK_ID_3 @tmux_room_pinned 1"
rm -f "$TMUX_STATE/new-room"

: > "$TMUX_LOG"
new_rollback_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_SET_FAIL_OPTION='@tmux_room_driver' TMUX_ROOM_DEVICE=devbox \
  "$SCRIPT" --new delta --driver codex 2>&1 || true)
assert_contains "$new_rollback_output" "Room creation rolled back after metadata setup failed: delta"
assert_contains "$(<"$TMUX_LOG")" "kill-session -t $MOCK_ID_3"
rm -f "$TMUX_STATE/new-room"

: > "$TMUX_LOG"
new_unverified_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_REVALIDATE_ID="$MOCK_ID_4" TMUX_ROOM_DEVICE=devbox \
  "$SCRIPT" --new delta 2>&1 || true)
assert_contains "$new_unverified_output" "Room creation rolled back because tmux did not preserve the requested identity"
assert_contains "$(<"$TMUX_LOG")" "kill-session -t $MOCK_ID_3"
rm -f "$TMUX_STATE/new-room"

: > "$TMUX_LOG"
invalid_agent_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --new gamma --agent 'codex;whoami' 2>&1 || true)
assert_contains "$invalid_agent_output" "Unsupported agent"
assert_not_contains "$(<"$TMUX_LOG")" "new-session"

: > "$TMUX_LOG"
arbitrary_command_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --new gamma --command whoami 2>&1 || true)
assert_contains "$arbitrary_command_output" "Unknown room creation option: --command"
assert_not_contains "$(<"$TMUX_LOG")" "new-session"

: > "$TMUX_LOG"
for unsafe_room in '--update' '--kill' '-room' '.hidden' 'room.with.dot'; do
  unsafe_room_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --new "$unsafe_room" 2>&1 || true)
  assert_contains "$unsafe_room_output" "Invalid room name"
done
invalid_rename=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --rename alpha room.with.dot 2>&1 || true)
assert_contains "$invalid_rename" "Invalid room name"
unsafe_local_action=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --inspect --kill 2>&1 || true)
assert_contains "$unsafe_local_action" "Invalid room name"
unsafe_id_action=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --attach-id 1 --update 2>&1 || true)
assert_contains "$unsafe_id_action" "Invalid room identity"
missing_kill_target=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill 2>&1 || true)
assert_contains "$missing_kill_target" "Usage: tmux-room --kill"
assert_not_contains "$(<"$TMUX_LOG")" "new-session"
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
remote_inspect_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --inspect mini:alpha)
assert_contains "$remote_inspect_output" "ROOM DETAILS"
assert_contains "$(<"$SSH_LOG")" "-o BatchMode=yes -o ConnectTimeout=6 -o ConnectionAttempts=1 mini-host env TMUX_ROOM_DEVICE=mini TMUX_ROOM_SOURCE_LABEL=remote tmux-room --inspect alpha"
assert_not_contains "$(<"$SSH_LOG")" "ssh -t"

: > "$SSH_LOG"
remote_json_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --json mini:alpha)
printf '%s' "$remote_json_output" | /usr/bin/python3 -c 'import json,sys; doc=json.load(sys.stdin); assert doc["schema_version"] == 1; assert doc["device"]["source"] == "remote"'
assert_contains "$(<"$SSH_LOG")" "tmux-room --json alpha"

: > "$SSH_LOG"
PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" mini:alpha >/dev/null
assert_contains "$(<"$SSH_LOG")" "-t mini-host tmux-room alpha"

: > "$SSH_LOG"
unsafe_remote=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --inspect 'mini:--kill' 2>&1 || true)
assert_contains "$unsafe_remote" "Invalid device or room name"
unsafe_remote=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" 'mini:--update' 2>&1 || true)
assert_contains "$unsafe_remote" "Invalid device or room name"
unsafe_remote=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" 'mini:room.with.dot' 2>&1 || true)
assert_contains "$unsafe_remote" "Invalid device or room name"
assert_not_contains "$(<"$SSH_LOG")" "mini-host"

AT_HOSTS="$MOCK/at-hosts"
printf '%s\n' 'mini@bad mini-host' > "$AT_HOSTS"
at_all_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$AT_HOSTS" "$SCRIPT" --all)
assert_contains "$at_all_output" "DEVICE: mini@bad [invalid host entry]"
: > "$SSH_LOG"
at_direct_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$AT_HOSTS" "$SCRIPT" --inspect 'mini@bad:alpha' 2>&1 || true)
assert_contains "$at_direct_output" "Invalid device or room name"
assert_not_contains "$(<"$SSH_LOG")" "mini-host"
at_fleet_json=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$AT_HOSTS" "$SCRIPT" --fleet-json)
printf '%s' "$at_fleet_json" | /usr/bin/python3 -c 'import json,sys; device=json.load(sys.stdin)["devices"][1]; assert device["status"] == "invalid"; assert device["error"] == "invalid_host_entry"'
assert_not_contains "$(<"$SSH_LOG")" "mini-host"
invalid_local_label=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE='mini@bad' "$SCRIPT" --json)
printf '%s' "$invalid_local_label" | /usr/bin/python3 -c 'import json,sys; assert json.load(sys.stdin)["device"]["name"] == "local"'
tainted_local_label=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=$'mini\n' "$SCRIPT" --json)
printf '%s' "$tainted_local_label" | /usr/bin/python3 -c 'import json,sys; assert json.load(sys.stdin)["device"]["name"] == "local"'

FLEET_HOSTS="$MOCK/fleet-hosts"
printf '%s\n' \
  'mini mini-host' \
  'down down-host' \
  'badjson badjson-host' \
  'tainted tainted-host' \
  'hugeint hugeint-host' \
  'large large-host' \
  'error error-host' > "$FLEET_HOSTS"
: > "$SSH_LOG"
fleet_json=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --fleet-json)
# shellcheck disable=SC2016
printf '%s' "$fleet_json" | /usr/bin/python3 -c '
import json
import sys
import unicodedata

document = json.load(sys.stdin)
assert document["schema"] == "tmux-room.fleet"
assert document["schema_version"] == 1
assert document["complete"] is False
devices = {device["name"]: device for device in document["devices"]}
assert list(devices) == ["devbox", "mini", "down", "badjson", "tainted", "hugeint", "large", "error"]
assert devices["devbox"]["status"] == "reachable"
assert devices["mini"]["status"] == "reachable"
assert devices["mini"]["source"] == "remote"
assert devices["mini"]["rooms"][0]["id"] == "$9"
assert devices["mini"]["rooms"][0]["name"] == "remote-review"
assert devices["mini"]["rooms"][0]["metadata"]["state"] == "needs_input"
assert devices["down"]["status"] == "unreachable"
assert devices["down"]["error"] == "connection_failed"
assert devices["badjson"]["status"] == "unsupported"
assert devices["badjson"]["error"] == "unsupported_schema"
assert devices["tainted"]["status"] == "invalid"
assert devices["tainted"]["error"] == "invalid_inventory"
assert devices["tainted"]["rooms"] == []
assert devices["hugeint"]["status"] == "invalid"
assert devices["hugeint"]["error"] == "invalid_inventory"
assert devices["large"]["status"] == "invalid"
assert devices["large"]["error"] == "inventory_too_large"
assert devices["large"]["rooms"] == []
assert devices["error"]["status"] == "unsupported"
assert devices["error"]["error"] == "remote_command_failed"

def strings(value):
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for key, item in value.items():
            yield from strings(key)
            yield from strings(item)
    elif isinstance(value, list):
        for item in value:
            yield from strings(item)

for value in strings(document):
    assert all(ch.isprintable() and not unicodedata.category(ch).startswith("C") for ch in value)
'
assert_not_contains "$fleet_json" "forged-device-name"
assert_not_contains "$fleet_json" "mini-host"
assert_not_contains "$fleet_json" "down-host"
assert_not_contains "$fleet_json" "badjson-host"
assert_not_contains "$fleet_json" "tainted-host"
assert_not_contains "$fleet_json" "hugeint-host"
assert_not_contains "$fleet_json" "large-host"
assert_not_contains "$fleet_json" "error-host"
assert_not_contains "$fleet_json" "must-not-leak"
assert_not_contains "$fleet_json" "unsafe"

fleet_alias=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --all --json)
printf '%s' "$fleet_alias" | /usr/bin/python3 -c 'import json,sys; document=json.load(sys.stdin); assert document["schema"] == "tmux-room.fleet"; assert len(document["devices"]) == 8'

fleet_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_COLUMNS=72 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --fleet)
assert_contains "$fleet_output" "FLEET: 8 devices, 2 reachable, 6 unavailable"
assert_contains "$fleet_output" "mini:remote-review"
assert_contains "$fleet_output" "!needs_input"
assert_contains "$fleet_output" "! down: unreachable"
assert_not_contains "$fleet_output" "mini-host"
assert_not_contains "$fleet_output" "must-not-leak"
assert_before "$fleet_output" "mini:remote-review" "devbox:alpha"
assert_max_display_width "$fleet_output" 72

narrow_fleet_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_COLUMNS=34 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --fleet)
for unavailable_device in down badjson tainted hugeint large error; do
  assert_contains "$narrow_fleet_output" "! $unavailable_device:"
done
assert_max_display_width "$narrow_fleet_output" 34

HANG_HOSTS="$MOCK/hang-hosts"
printf '%s\n' 'hang hang-host' > "$HANG_HOSTS"
SECONDS=0
timeout_fleet_json=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_REMOTE_TIMEOUT_SECONDS=1 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$HANG_HOSTS" "$SCRIPT" --fleet-json)
((SECONDS <= 4)) || fail "fleet wall-clock timeout took too long"
printf '%s' "$timeout_fleet_json" | /usr/bin/python3 -c '
import json, sys
device = json.load(sys.stdin)["devices"][1]
assert device["name"] == "hang"
assert device["status"] == "unreachable"
assert device["error"] == "collection_timeout"
'

: > "$SSH_LOG"
fleet_picker_output=$(printf '/remote-review\n\nn\nq' | PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" \
  TMUX_ROOM_FORCE_ARROW=1 TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_COLUMNS=80 \
  TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --fleet)
assert_contains "$fleet_picker_output" "SEARCH: remote-review"
assert_contains "$fleet_picker_output" "ROOM DETAILS"
assert_contains "$fleet_picker_output" "Attachment cancelled"
assert_contains "$(<"$SSH_LOG")" "-o BatchMode=yes -o ConnectTimeout=6 -o ConnectionAttempts=1"
assert_contains "$(<"$SSH_LOG")" "tmux-room --inspect-id 9 remote-review"
assert_not_contains "$(<"$SSH_LOG")" "-t mini-host tmux-room --inspect-id"

: > "$SSH_LOG"
printf '/remote-review\n\ny\n' | PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" \
  TMUX_ROOM_FORCE_ARROW=1 TMUX_ROOM_REMOTE_MAX_BYTES=1024 TMUX_ROOM_COLUMNS=80 \
  TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$FLEET_HOSTS" "$SCRIPT" --fleet >/dev/null
assert_contains "$(<"$SSH_LOG")" "-t -o BatchMode=yes -o ConnectTimeout=6 -o ConnectionAttempts=1 mini-host tmux-room --attach-id 9 remote-review"

: > "$TMUX_LOG"
protected_kill_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_META_PROTECTED="${ESC}1${BIDI}" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$protected_kill_output" "Kill refused: room is protected"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
conservative_protected=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_META_PROTECTED=off TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$conservative_protected" "Kill refused: room is protected"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
PROTECTED_COUNTER="$MOCK/protected-counter"
rm -f "$PROTECTED_COUNTER"
protected_after_confirmation=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_PROTECTED_COUNTER="$PROTECTED_COUNTER" TMUX_PROTECTED_AFTER=3 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$protected_after_confirmation" "Kill aborted: room became protected after confirmation"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
rm -f "$PROTECTED_COUNTER"
protected_during_snapshot=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_PROTECTED_COUNTER="$PROTECTED_COUNTER" TMUX_PROTECTED_AFTER=4 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$protected_during_snapshot" "Kill aborted: room became protected during final snapshot"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
guard_read_failure=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_GUARD_READ_FAIL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$guard_read_failure" "Kill refused: unable to verify the room protection state"
assert_not_contains "$(<"$TMUX_LOG")" "atomic-kill"

: > "$TMUX_LOG"
atomic_blocked=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ATOMIC_BLOCK=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$atomic_blocked" "final tmux protection predicate blocked termination"
assert_contains "$(<"$TMUX_LOG")" "if-shell -F -t $MOCK_ID_1:"
assert_not_contains "$(<"$TMUX_LOG")" "atomic-kill"

: > "$TMUX_LOG"
atomic_failure=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ATOMIC_FAIL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$atomic_failure" "tmux could not evaluate the final protection predicate"
assert_not_contains "$(<"$TMUX_LOG")" "atomic-kill"

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
assert_contains "$(<"$TMUX_LOG")" "if-shell -F -t $MOCK_ID_1:"
assert_contains "$(<"$TMUX_LOG")" '#{||:#{==:#{@tmux_room_protected},},#{==:#{@tmux_room_protected},0}}'
assert_contains "$(<"$TMUX_LOG")" "atomic-kill $MOCK_ID_1"
assert_contains "$(<"$TMUX_LOG")" "display-message -p -t $MOCK_ID_1: #{session_id}|#{session_name}"
assert_contains "$(<"$TMUX_LOG")" "list-panes -s -t $MOCK_ID_1 -F #{pane_pid}"
assert_not_contains "$(<"$TMUX_LOG")" '-t =alpha'

: > "$TMUX_LOG"
race_output=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha || true)
assert_contains "$race_output" "Kill aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
ID_COUNTER="$MOCK/id-counter"
snapshot_race_output=$(printf 'alpha\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ID_COUNTER="$ID_COUNTER" TMUX_SECOND_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha || true)
assert_contains "$snapshot_race_output" "Kill aborted: room identity changed during final snapshot"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
arrow_close_output=$(printf '\033[Bxbeta\nKILL\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$arrow_close_output" "Killed room: beta"
assert_contains "$(<"$TMUX_LOG")" "kill-session -t \$2"

search_output=$(printf '/beta\nq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$search_output" "SEARCH: beta"
assert_filtered_screen "$search_output" "beta" "beta" "alpha"

note_search_output=$(printf '/review requested\nq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ATTENTION_FIXTURE=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_filtered_screen "$note_search_output" "review requested" "beta" "alpha"

driver_search_output=$(printf '/claude\nq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ATTENTION_FIXTURE=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_filtered_screen "$driver_search_output" "claude" "beta" "alpha"

state_search_output=$(printf '/needs_input\nq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ATTENTION_FIXTURE=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_filtered_screen "$state_search_output" "needs_input" "beta" "alpha"

clear_output=$(printf '/beta\ncq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_filtered_screen "$clear_output" "beta" "beta" "alpha"
assert_cleared_screen "$clear_output" "alpha" "beta"

: > "$TMUX_LOG"
no_match_output=$(printf '/missing-room\nxq' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_contains "$no_match_output" "No rooms match this search."
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

dirty_search_output=$(printf '/beta%s\nq' "$BIDI" | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_TWO_ROOMS=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
assert_not_contains "$dirty_search_output" "$BIDI"

SECONDS=0
delayed_escape_output=$({ printf '\033'; sleep 2; printf 'q'; } | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT")
((SECONDS <= 4)) || fail "local picker blocked on a lone Escape key"
assert_not_contains "$delayed_escape_output" "ROOM DETAILS"

EMPTY_HOSTS="$MOCK/empty-hosts"
: > "$EMPTY_HOSTS"
fleet_escape_output=$(printf '\033q' | PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_FORCE_ARROW=1 TMUX_ROOM_DEVICE=devbox TMUX_ROOM_HOSTS_FILE="$EMPTY_HOSTS" "$SCRIPT" --fleet)
assert_not_contains "$fleet_escape_output" "ROOM DETAILS"

: > "$TMUX_LOG"
cleanup_cancel_output=$(printf 'NO\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_cancel_output" "STALE ROOM REVIEW"
assert_contains "$cleanup_cancel_output" "beta"
assert_contains "$cleanup_cancel_output" "Cleanup cancelled"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
cleanup_output=$(printf 'CLEANUP 1\nKILL STALE\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_output" "Cleaned stale room: beta"
assert_contains "$cleanup_output" "Cleanup complete: 1 cleaned, 0 skipped"
assert_contains "$(<"$TMUX_LOG")" "display-message -p -t $MOCK_ID_2: #{session_id}|#{session_attached}|#{session_activity}|#{@tmux_room_pinned}|#{@tmux_room_protected}"
assert_contains "$(<"$TMUX_LOG")" "if-shell -F -t $MOCK_ID_2:"
assert_contains "$(<"$TMUX_LOG")" '#{==:#{session_attached},0}'
assert_contains "$(<"$TMUX_LOG")" '#{||:#{==:#{@tmux_room_pinned},},#{==:#{@tmux_room_pinned},0}}'
assert_contains "$(<"$TMUX_LOG")" '#{==:#{session_activity},1700003600}'
assert_contains "$(<"$TMUX_LOG")" "atomic-kill $MOCK_ID_2"
assert_contains "$(<"$TMUX_LOG")" "kill-session -t $MOCK_ID_2"

: > "$TMUX_LOG"
SNAPSHOT_COUNTER="$MOCK/cleanup-snapshot-counter"
rm -f "$SNAPSHOT_COUNTER"
cleanup_attach_race=$(printf 'CLEANUP 1\nKILL STALE\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_SNAPSHOT_COUNTER="$SNAPSHOT_COUNTER" TMUX_FINAL_ATTACHED=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_attach_race" "Skipped room changed during final snapshot: beta"
assert_contains "$cleanup_attach_race" "Cleanup complete: 0 cleaned, 1 skipped"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

: > "$TMUX_LOG"
rm -f "$SNAPSHOT_COUNTER"
cleanup_activity_race=$(printf 'CLEANUP 1\nKILL STALE\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_SNAPSHOT_COUNTER="$SNAPSHOT_COUNTER" TMUX_FINAL_ACTIVITY="$(date +%s)" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_activity_race" "Skipped room changed during final snapshot: beta"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"

cleanup_pinned=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_META_PINNED="${ESC}1${BIDI}" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_pinned" "No stale rooms are eligible for cleanup"

cleanup_conservative_pinned=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_META_PINNED=off TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_conservative_pinned" "No stale rooms are eligible for cleanup"

cleanup_guard_failure=$(PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_GUARD_READ_FAIL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_guard_failure" "No stale rooms are eligible for cleanup"

: > "$TMUX_LOG"
cleanup_atomic_block=$(printf 'CLEANUP 1\nKILL STALE\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ATOMIC_BLOCK=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_atomic_block" "Skipped room blocked by the final tmux safety predicate: beta"
assert_contains "$cleanup_atomic_block" "Cleanup complete: 0 cleaned, 1 skipped"
assert_not_contains "$(<"$TMUX_LOG")" "atomic-kill"

: > "$TMUX_LOG"
cleanup_atomic_failure=$(printf 'CLEANUP 1\nKILL STALE\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_TWO_ROOMS=1 TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ATOMIC_FAIL=1 TMUX_ROOM_DEVICE=devbox "$SCRIPT" --cleanup-stale --days 7)
assert_contains "$cleanup_atomic_failure" "tmux could not evaluate the final safety predicate: beta"
assert_contains "$cleanup_atomic_failure" "Cleanup complete: 0 cleaned, 1 skipped"
assert_not_contains "$(<"$TMUX_LOG")" "atomic-kill"

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
assert_contains "$dirty_output" "DEVICE: local [local]"
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
assert_contains "$empty_output" "No rooms are available."

command -v tmux >/dev/null 2>&1 || fail "real tmux is required for boundary tests"
REAL_TMUX_BIN=$(command -v tmux)
REAL_TMUX_SOCKET="tmux-room-test-$$"
REAL_BIN="$MOCK/real-bin"
mkdir -p "$REAL_BIN"
cat > "$REAL_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ -n "${TMUX_REAL_FAIL_SET_ONCE_OPTION:-}" && "${1:-}" == "set-option" && \
      -n "${TMUX_REAL_FAIL_COUNTER:-}" && ! -f "$TMUX_REAL_FAIL_COUNTER" ]]; then
  for argument in "$@"; do
    if [[ "$argument" == "$TMUX_REAL_FAIL_SET_ONCE_OPTION" ]]; then
      : > "$TMUX_REAL_FAIL_COUNTER"
      exit 98
    fi
  done
fi
if [[ "${TMUX_REAL_PROTECT_ON_IF:-0}" == "1" && "${1:-}" == "if-shell" ]]; then
  previous=""
  target=""
  for argument in "$@"; do
    if [[ "$previous" == "-t" ]]; then
      target="${argument%:}"
      break
    fi
    previous="$argument"
  done
  [[ -n "$target" ]] || exit 97
  "$TMUX_REAL_BIN" -L "$TMUX_REAL_SOCKET" set-option -t "$target" @tmux_room_protected 1
fi
exec "$TMUX_REAL_BIN" -L "$TMUX_REAL_SOCKET" "$@"
EOF
chmod +x "$REAL_BIN/tmux"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" -f /dev/null new-session -d -s live-room -c "$MOCK/workspace"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" new-session -d -s 'a|b' -c "$MOCK/workspace"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" new-session -d -s boundary-room -c "$MOCK/workspace"
real_dot_create=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --new 'room.with.dot' 2>&1 || true)
assert_contains "$real_dot_create" "Invalid room name"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" has-session -t room_with_dot 2>/dev/null && fail "dotted room creation reached tmux"

real_pipe_json=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --json 'a|b')
printf '%s' "$real_pipe_json" | /usr/bin/python3 -c 'import json,sys; room=json.load(sys.stdin)["rooms"][0]; assert room["name"] == "a|b"; assert room["id"].startswith("$")'
real_pipe_inspect=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --inspect 'a|b')
assert_contains "$real_pipe_inspect" "ROOM: a|b"

"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_driver claude
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_state idle
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_state_at 1700000000
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_note $'old note\n'
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_pinned 0
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" set-option -t live-room @tmux_room_protected 0
REAL_NOTE_BEFORE="$MOCK/real-note-before"
REAL_NOTE_AFTER="$MOCK/real-note-after"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_note > "$REAL_NOTE_BEFORE"
REAL_FAIL_COUNTER="$MOCK/real-set-fail-once"
real_metadata_failure=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" \
  TMUX_REAL_FAIL_SET_ONCE_OPTION='@tmux_room_protected' TMUX_REAL_FAIL_COUNTER="$REAL_FAIL_COUNTER" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --metadata live-room --driver codex --state needs_input --note "new note" --pinned --protected 2>&1 || true)
assert_contains "$real_metadata_failure" "restored the previous metadata snapshot"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_driver)" == "claude" ]] || fail "real metadata rollback lost driver"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_state)" == "idle" ]] || fail "real metadata rollback lost state"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_state_at)" == "1700000000" ]] || fail "real metadata rollback lost state timestamp"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_pinned)" == "0" ]] || fail "real metadata rollback lost pinned value"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_protected)" == "0" ]] || fail "real metadata rollback lost protected value"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t live-room @tmux_room_note > "$REAL_NOTE_AFTER"
cmp "$REAL_NOTE_BEFORE" "$REAL_NOTE_AFTER" >/dev/null 2>&1 || fail "real metadata rollback lost the exact note value"

real_metadata=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --metadata live-room --driver codex --state idle --note "real tmux" --protected)
assert_contains "$real_metadata" "Updated room metadata: live-room"
real_json=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --json live-room)
printf '%s' "$real_json" | /usr/bin/python3 -c '
import json, sys
room = json.load(sys.stdin)["rooms"][0]
assert room["id"].startswith("$")
assert room["metadata"]["driver"] == "codex"
assert room["metadata"]["state"] == "idle"
assert room["metadata"]["fresh"] is True
assert room["metadata"]["protected"] is True
'

real_rename=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --rename live-room renamed-room)
assert_contains "$real_rename" "Renamed room: live-room to renamed-room"
real_protected=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --kill renamed-room 2>&1 || true)
assert_contains "$real_protected" "Kill refused: room is protected"

PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --metadata renamed-room --unprotected >/dev/null
real_boundary=$(printf 'boundary-room\nKILL\n' | PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" \
  TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_REAL_PROTECT_ON_IF=1 TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --kill boundary-room 2>&1 || true)
assert_contains "$real_boundary" "final tmux protection predicate blocked termination"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" has-session -t boundary-room 2>/dev/null || fail "real tmux boundary mutation did not preserve the room"
[[ "$("$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" show-options -v -t boundary-room @tmux_room_protected)" == "1" ]] || \
  fail "real tmux boundary mutation was not observed"
"$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" kill-session -t boundary-room

real_kill=$(printf 'renamed-room\nKILL\n' | PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --kill renamed-room)
assert_contains "$real_kill" "Killed room: renamed-room"
real_pipe_kill=$(printf 'a|b\nKILL\n' | PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
  "$SCRIPT" --kill 'a|b')
assert_contains "$real_pipe_kill" "Killed room: a|b"
REAL_TMUX_SOCKET=""

echo "tests passed"
