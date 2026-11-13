# Agent Instructions

## Code Review Rules

These rules are for automated reviewers (Codex, CodeRabbit, Cursor Bugbot) and for
agents triaging their findings.

### What counts as a blocker

- Flag as P0/P1 only a concrete failure this PR introduces: security hole,
  credential exposure, auth or tenant-scope bypass, data loss or corruption,
  destructive or incorrect behavior, broken compatibility, or an unmet
  acceptance criterion from the PR description. Name the file and the failure.
- Style, naming, refactors, optional hardening, and pre-existing problems are
  follow-ups. Say "follow-up" and do not block on them.
- Any literal secret, token, API key, password, private key, or database URL
  with a password is always a blocker, including in tests, docs, and scripts.

### Auth and tenant scope

- Every route, server action, or handler that touches tenant data authenticates
  first and scopes by org/project membership, never by a record id from the
  request alone. Safe path: the repo's scope helper (name it here, for example
  `requireOrgRole` or `resolveProjectScope`).
- Webhooks verify the provider signature before parsing the body.

### Money and client communications

- Prices, amounts, and discounts are computed and validated on the server, in
  integer minor units. A client-supplied amount is never trusted.
- Client-facing copy (emails, notifications, templates, user guides, portal
  text) must not state prices, rates, quotes, or estimates unless the PR
  description says Elliot approved that wording.

### Repo-specific

- Shell scripts must stay bash-portable: macOS bash 3.2 and Linux. Flag bash-4-only constructs (associative arrays, `mapfile`/`readarray`, `${var,,}`, `&>>`), GNU-only flags (`sed -i` without a suffix, `readlink -f`, `date -d`), and unguarded `timeout`. Safe path: POSIX-compatible syntax or a guarded fallback.
- Flag `rm -rf` on a variable that can be empty, and any force-push or destructive git command.

### Handling review findings (agents)

- Verify every finding against the current head before acting; labels are
  evidence, not verdicts.
- Fix verified blockers in this PR. Reply with the disposition (fixed in
  `<sha>`, follow-up #N, not applicable because ...) and resolve the thread.
- Do not merge with an unresolved, non-outdated P0/P1 thread or an unresolved
  CodeRabbit "Potential issue" (Critical/Major) thread.
