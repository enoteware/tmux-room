#!/usr/bin/env bash
set -eo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$ROOT/bin/tmux-room"

bash -n "$SCRIPT"
[[ "$($SCRIPT --version)" == "tmux-room 0.1.0" ]]
$SCRIPT --help | grep -q 'Interactive room picker'

MOCK=$(mktemp -d)
trap 'rm -rf "$MOCK"' EXIT
cat > "$MOCK/tmux" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "has-session" ]]; then exit 1; fi
exit 0
EOF
chmod +x "$MOCK/tmux"
output=$(PATH="$MOCK:$PATH" "$SCRIPT")
[[ "$output" == "No tmux rooms are running." ]]

echo "tests passed"
