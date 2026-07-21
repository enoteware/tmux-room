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
[[ "$($SCRIPT --version)" == "tmux-room 0.3.0" ]] || fail "version should be 0.3.0"
help=$($SCRIPT --help)
assert_contains "$help" "--all"
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
    if [[ "$*" == *'#{session_id}|#{session_name}|#{session_attached}|#{session_activity}'* ]]; then
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
    case "$*" in
      *'#{pane_pid}|#{pane_current_path}'*) echo '4242|/work/knowledge-hub|node|review' ;;
      *'#{pane_current_path}'*) echo '/work/knowledge-hub' ;;
      *'#{pane_pid}'*) echo '4242' ;;
    esac
    ;;
  show-options)
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
printf '{"tag_name":"v9.9.9"}\n'
EOF

cat > "$MOCK/ssh" <<'EOF'
#!/usr/bin/env bash
[[ -n "${SSH_MOCK_LOG:-}" ]] && printf '%s\n' "$*" >> "$SSH_MOCK_LOG"
case "$*" in
  *'tmux-room --json alpha'*)
    printf '%s\n' '{"schema":"tmux-room.inventory","schema_version":1,"device":{"name":"mini","source":"remote"},"rooms":[{"id":"$9","name":"alpha"}]}'
    exit 0
    ;;
  *'tmux-room --inspect alpha'*)
    echo 'ROOM DETAILS'
    echo '  ROOM: alpha [detached]'
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

output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --list)
assert_contains "$output" "DEVICE: devbox [local]"
assert_contains "$output" "STATUS: CPU 12% load (0.96/8) · RAM 44% (13.9/31.3 GB)"
assert_contains "$output" "#  ROOM"
assert_contains "$output" "PROVIDER/MODEL"
assert_contains "$output" "claude-fable5-low"
assert_contains "$output" "alpha"
assert_contains "$output" "attached"
assert_contains "$output" "2023-11-14 23:13"
assert_not_contains "$output" "AGENTS:"
assert_not_contains "$output" "REPO:"
assert_not_contains "$output" "SUMMED RSS SNAPSHOT:"

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

inspect_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_ROOM_DEVICE=devbox TMUX_META_DRIVER=codex TMUX_META_STATE=idle TMUX_META_STATE_AT="$NOW" TMUX_META_NOTE="review ready" "$SCRIPT" --inspect alpha)
assert_contains "$inspect_output" "ROOM DETAILS"
assert_contains "$inspect_output" "METADATA: driver codex · state idle · pinned no · protected no"
assert_contains "$inspect_output" "NOTE: review ready"

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
attach_race_output=$(printf '1\ny\n' | PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_REVALIDATE_ID="\$2" TMUX_ROOM_DEVICE=devbox "$SCRIPT" || true)
assert_contains "$attach_race_output" "Attachment aborted: room identity changed"
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
assert_contains "$metadata_race_output" "Metadata update aborted: room identity changed"
assert_not_contains "$(<"$TMUX_LOG")" "set-option"

TMUX_STATE="$MOCK/tmux-state"
mkdir -p "$TMUX_STATE" "$MOCK/workspace"
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
assert_contains "$(<"$TMUX_LOG")" "new-session -d -P -F #{session_id} -s gamma -c $MOCK/workspace codex"
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
assert_contains "$new_unverified_output" "Room creation succeeded, but setup failed"
assert_contains "$new_unverified_output" "The unverified room was not removed"
assert_not_contains "$(<"$TMUX_LOG")" "kill-session"
rm -f "$TMUX_STATE/new-room"

: > "$TMUX_LOG"
invalid_agent_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --new gamma --agent 'codex;whoami' 2>&1 || true)
assert_contains "$invalid_agent_output" "Unsupported agent"
assert_not_contains "$(<"$TMUX_LOG")" "new-session"

: > "$TMUX_LOG"
arbitrary_command_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_MOCK_STATE_DIR="$TMUX_STATE" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --new gamma --command whoami 2>&1 || true)
assert_contains "$arbitrary_command_output" "Unknown room creation option: --command"
assert_not_contains "$(<"$TMUX_LOG")" "new-session"

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
assert_contains "$(<"$SSH_LOG")" "-o BatchMode=yes mini-host env TMUX_ROOM_DEVICE=mini TMUX_ROOM_SOURCE_LABEL=remote tmux-room --inspect alpha"
assert_not_contains "$(<"$SSH_LOG")" "ssh -t"

: > "$SSH_LOG"
remote_json_output=$(PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" --json mini:alpha)
printf '%s' "$remote_json_output" | /usr/bin/python3 -c 'import json,sys; doc=json.load(sys.stdin); assert doc["schema_version"] == 1; assert doc["device"]["source"] == "remote"'
assert_contains "$(<"$SSH_LOG")" "tmux-room --json alpha"

: > "$SSH_LOG"
PATH="$MOCK:/usr/bin:/bin" SSH_MOCK_LOG="$SSH_LOG" TMUX_ROOM_HOSTS_FILE="$HOSTS" "$SCRIPT" mini:alpha >/dev/null
assert_contains "$(<"$SSH_LOG")" "-t mini-host tmux-room alpha"

: > "$TMUX_LOG"
protected_kill_output=$(PATH="$MOCK:/usr/bin:/bin" TMUX_MOCK_LOG="$TMUX_LOG" TMUX_META_PROTECTED="${ESC}1${BIDI}" TMUX_ROOM_DEVICE=devbox "$SCRIPT" --kill alpha 2>&1 || true)
assert_contains "$protected_kill_output" "Kill refused: room is protected"
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
assert_contains "$(<"$TMUX_LOG")" "display-message -p -t $MOCK_ID_2: #{session_id}|#{session_name}|#{session_attached}|#{session_activity}"
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

if command -v tmux >/dev/null 2>&1; then
  REAL_TMUX_BIN=$(command -v tmux)
  REAL_TMUX_SOCKET="tmux-room-test-$$"
  REAL_BIN="$MOCK/real-bin"
  mkdir -p "$REAL_BIN"
  cat > "$REAL_BIN/tmux" <<'EOF'
#!/usr/bin/env bash
exec "$TMUX_REAL_BIN" -L "$TMUX_REAL_SOCKET" "$@"
EOF
  chmod +x "$REAL_BIN/tmux"
  "$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" -f /dev/null new-session -d -s live-room -c "$MOCK/workspace"
  "$REAL_TMUX_BIN" -L "$REAL_TMUX_SOCKET" new-session -d -s 'a|b' -c "$MOCK/workspace"

  real_pipe_json=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
    "$SCRIPT" --json 'a|b')
  printf '%s' "$real_pipe_json" | /usr/bin/python3 -c 'import json,sys; room=json.load(sys.stdin)["rooms"][0]; assert room["name"] == "a|b"; assert room["id"].startswith("$")'
  real_pipe_inspect=$(PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
    "$SCRIPT" --inspect 'a|b')
  assert_contains "$real_pipe_inspect" "ROOM: a|b"

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
  real_kill=$(printf 'renamed-room\nKILL\n' | PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
    "$SCRIPT" --kill renamed-room)
  assert_contains "$real_kill" "Killed room: renamed-room"
  real_pipe_kill=$(printf 'a|b\nKILL\n' | PATH="$REAL_BIN:/usr/bin:/bin" TMUX_REAL_BIN="$REAL_TMUX_BIN" TMUX_REAL_SOCKET="$REAL_TMUX_SOCKET" TMUX_ROOM_DISABLE_UPDATE_CHECK=1 \
    "$SCRIPT" --kill 'a|b')
  assert_contains "$real_pipe_kill" "Killed room: a|b"
  REAL_TMUX_SOCKET=""
fi

echo "tests passed"
