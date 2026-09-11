#!/bin/sh
# corax test suite. Plain POSIX sh on purpose: no bats, no shunit2, nothing to
# install. It must run on a bare server and on a Mac without a single dependency
# that corax itself does not already need.
#
# Usage: tests/run.sh
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
CORAX=${CORAX:-$ROOT/corax}

WORK=$(mktemp -d "${TMPDIR:-/tmp}/corax-tests.XXXXXX") || exit 1
trap 'rm -rf "$WORK"' EXIT INT TERM

PASS=0
FAIL=0

# --- harness -----------------------------------------------------------------

ok()   { PASS=$((PASS + 1)); printf '  \033[32m.\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  \033[31mX\033[0m %s\n' "$1"
         printf '      want: %s\n      got:  %s\n' "$2" "$3"; }
is()   { [ "$2" = "$3" ] && ok "$1" || bad "$1" "$2" "$3"; }

# The command transport is the test double: it appends the message to a file,
# so a test can assert on exactly what would have been sent.
cat > "$WORK/sink.sh" <<'SINK'
#!/bin/sh
printf '%s\n' "$1" >> "$CORAX_SINK"
SINK
chmod +x "$WORK/sink.sh"

mkconfig() {
  # mkconfig [extra lines...]
  {
    printf 'CORAX_TRANSPORT=command\n'
    printf 'CORAX_COMMAND=%s/sink.sh\n' "$WORK"
    for _l in "$@"; do printf '%s\n' "$_l"; done
  } > "$WORK/config"
}

reset() {
  : > "$WORK/sink"
  rm -rf "$WORK/state"
  mkdir -p "$WORK/state"
  mkconfig "$@"
}

# send <payload> [env assignments...] -> prints what the sink received
send() {
  _p=$1; shift
  printf '%s' "$_p" | env \
    CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" TMPDIR="$WORK/state" \
    "$@" sh "$CORAX" >/dev/null 2>&1
  cat "$WORK/sink"
}

# count <payload> [env...] -> how many messages the sink now holds
count() {
  send "$@" >/dev/null
  # one message is two lines
  _n=$(wc -l < "$WORK/sink" | tr -d ' ')
  echo $((_n / 2))
}

# backdate <session> <class> <seconds-ago>
backdate() {
  _d="$WORK/state/corax-$(id -u 2>/dev/null || echo u)"
  mkdir -p "$_d"
  printf '%s' "$(( $(date +%s) - $3 ))" > "$_d/$1.$2"
}

payload() {
  # payload <event> <notification_type> <cwd> <session> [extra json]
  printf '{"hook_event_name":"%s"' "$1"
  [ -n "$2" ] && printf ',"notification_type":"%s"' "$2"
  printf ',"cwd":"%s","session_id":"%s"%s}' "$3" "$4" "${5:-}"
}

# --- the message line --------------------------------------------------------

printf '\nidentity line\n'

reset
GITREPO="$WORK/proj"
mkdir -p "$GITREPO"
( cd "$GITREPO" && git init -q && git config user.email t@t && git config user.name t &&
  : > f && git add f && git commit -qm init ) >/dev/null 2>&1
HOST=$(hostname -s 2>/dev/null || hostname); HOST=${HOST%%.*}

got=$(send "$(payload Notification permission_prompt "$GITREPO" a1)" | head -1)
is "folder and branch, never the full path" "[corax] $HOST · proj · main" "$got"

reset
got=$(send "$(payload Stop '' /tmp b1)" | head -1)
is "no branch outside a repo, and no error" "[corax] $HOST · tmp" "$got"

reset
( cd "$GITREPO" && git worktree add -q --detach "$WORK/wt" HEAD &&
  git -C "$WORK/wt" checkout -q -b side ) >/dev/null 2>&1
got=$(send "$(payload Notification idle_prompt "$WORK/wt" c1)" | head -1)
is "a linked worktree is marked" "[corax] $HOST · wt · side (worktree)" "$got"

reset
( cd "$WORK/wt" && git checkout -q --detach HEAD ) >/dev/null 2>&1
SHA=$(git -C "$WORK/wt" rev-parse --short HEAD 2>/dev/null)
got=$(send "$(payload Notification idle_prompt "$WORK/wt" c2)" | head -1)
is "a detached head shows its sha, not the word HEAD" \
   "[corax] $HOST · wt · detached $SHA (worktree)" "$got"

reset 'CORAX_REDACT=1'
got=$(send "$(payload Notification permission_prompt "$GITREPO" d1)" | head -1)
is "redaction drops the folder and branch" "[corax] $HOST" "$got"

# --- the reason line ---------------------------------------------------------

printf '\nreason line\n'

for pair in 'permission_prompt|needs permission to run a tool' \
            'idle_prompt|is waiting for your input' \
            'agent_needs_input|has a subagent waiting on you' \
            'agent_completed|finished a background agent'; do
  nt=${pair%%|*}; want=${pair#*|}
  reset
  got=$(send "$(payload Notification "$nt" /tmp "r-$nt")" | sed -n 2p)
  is "$nt" "$want" "$got"
done

reset
got=$(send "$(payload Stop '' /tmp r-stop)" | sed -n 2p)
is "Stop" "finished a turn" "$got"

reset
got=$(printf '{"hook_event_name":"Notification","message":"Claude needs your permission","cwd":"/tmp","session_id":"r-legacy"}' \
  | env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1; sed -n 2p "$WORK/sink")
is "older payload with message and no notification_type" "Claude needs your permission" "$got"

# --- dedupe ------------------------------------------------------------------
# The two regressions this suite exists to prevent.

printf '\ndedupe\n'

reset
backdate d1 turn 60
is "idle 60s after a turn stays quiet (window is 90, not 45)" \
   0 "$(count "$(payload Notification idle_prompt /tmp d1)")"

reset
backdate d2 turn 30
is "a permission prompt is never swallowed by a turn message" \
   1 "$(count "$(payload Notification permission_prompt /tmp d2)")"

reset
backdate d3 turn 120
is "a turn message sends again after the window" \
   1 "$(count "$(payload Notification idle_prompt /tmp d3)")"

reset
backdate d4 perm 10
is "a repeated permission prompt is suppressed inside 20s" \
   0 "$(count "$(payload Notification permission_prompt /tmp d4)")"

reset
backdate d5 perm 30
is "a repeated permission prompt sends again after 20s" \
   1 "$(count "$(payload Notification permission_prompt /tmp d5)")"

reset
backdate d6 turn 5
is "sessions dedupe independently" \
   1 "$(count "$(payload Notification idle_prompt /tmp d7)")"

# --- guards ------------------------------------------------------------------

printf '\nguards\n'

reset
is "a nested Stop does nothing" \
   0 "$(count "$(payload Stop '' /tmp g1 ',"stop_hook_active":true')")"

reset
is "a subagent Stop does nothing" \
   0 "$(count "$(payload Stop '' /tmp g2 ',"agent_id":"sub-1"')")"

reset 'CORAX_ENABLED=0'
is "CORAX_ENABLED=0 silences everything" \
   0 "$(count "$(payload Notification permission_prompt /tmp g3)")"

reset 'CORAX_STOP=0'
is "CORAX_STOP=0 silences Stop" \
   0 "$(count "$(payload Stop '' /tmp g4)")"

reset 'CORAX_STOP=0'
is "CORAX_STOP=0 leaves permission prompts alone" \
   1 "$(count "$(payload Notification permission_prompt /tmp g5)")"

reset
mkdir -p "$WORK/private" && : > "$WORK/private/.no-corax"
is ".no-corax opts a project out" \
   0 "$(count "$(payload Notification permission_prompt "$WORK/private" g6)")"

reset
printf '%s' "$(payload Notification permission_prompt /tmp g7)" \
  | env CORAX_CONFIG=/nonexistent CORAX_SINK="$WORK/sink" TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
is "no config is a silent no-op" 0 "$(( $(wc -l < "$WORK/sink") / 2 ))"

# --- invariants --------------------------------------------------------------

printf '\ninvariants\n'

reset
out=$(printf '%s' "$(payload Notification permission_prompt /tmp i1)" \
  | env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" TMPDIR="$WORK/state" sh "$CORAX" 2>/dev/null)
is "hook mode writes nothing to stdout" "" "$out"

reset
for p in "$(payload Notification permission_prompt /tmp x1)" \
         "$(payload Stop '' /nonexistent-dir x2)" \
         '{"garbage"' \
         '{}' \
         ''; do
  printf '%s' "$p" | env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" \
    TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] || { bad "hook mode always exits 0" 0 "$rc"; break; }
done
[ "$rc" -eq 0 ] && ok "hook mode always exits 0, even on junk input"

reset
got=$(send "$(payload Notification permission_prompt "$GITREPO" q1)" | head -1)
( cd "$GITREPO" && git checkout -q -b 'weird"branch' ) >/dev/null 2>&1
reset
got=$(send "$(payload Notification permission_prompt "$GITREPO" q2)" | head -1)
is "a quote in a branch name survives intact" "[corax] $HOST · proj · weird\"branch" "$got"

# --- hostile input -----------------------------------------------------------
# A directory name may legally contain a newline, so without stripping it a
# folder could forge the reason line. A branch name cannot contain one, but a
# folder can, and the folder name is attacker-influenceable via a cloned repo.

printf '\nhostile input\n'

reset
NL=$(printf 'a\nFORGED REASON')
mkdir -p "$WORK/$NL" 2>/dev/null
if [ -d "$WORK/$NL" ]; then
  got=$(send "$(payload Notification permission_prompt "$WORK/$NL" h1)" | wc -l | tr -d ' ')
  is "a newline in a folder name cannot forge a line" 2 "$got"
else
  ok "a newline in a folder name cannot forge a line (skipped, fs refused it)"
fi

reset
LONG=$(printf 'x%.0s' 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 \
                       1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0 \
                       1 2 3 4 5 6 7 8 9 0 1 2 3 4 5 6 7 8 9 0)
mkdir -p "$WORK/$LONG"
got=$(send "$(payload Notification permission_prompt "$WORK/$LONG" h2)" | head -1)
len=$(printf '%s' "$got" | wc -c | tr -d ' ')
[ "$len" -lt 120 ] && ok "a very long folder name is truncated" \
  || bad "a very long folder name is truncated" "<120 bytes" "$len bytes"

reset
# A Stop payload carries last_assistant_message: arbitrary model output. No
# backend may take a field value out of it.
DECOY='{"hook_event_name":"Stop","cwd":"/tmp","session_id":"h3","last_assistant_message":"I wrote cwd: /etc/decoy and notification_type: permission_prompt"}'
got=$(send "$DECOY")
case "$got" in
  *decoy*) bad "model output cannot supply a field value" "no decoy" "$got" ;;
  *) ok "model output cannot supply a field value" ;;
esac

reset
got=$(send "$(payload Notification unknown_future_type /tmp h4)" | sed -n 2p)
is "an unknown notification type still notifies, generically" "needs your attention" "$got"

reset
got=$(printf '{"hook_event_name":"Notification","message":"tool: Bash\u0007\u000abogus","cwd":"/tmp","session_id":"h5"}' \
  | env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1; wc -l < "$WORK/sink" | tr -d ' ')
is "payload text cannot inject extra lines" 2 "$got"

# --- CLI ---------------------------------------------------------------------

printf '\ncli\n'

is "version" "corax $(sed -n 's/^CORAX_VERSION=//p' "$CORAX" | head -1)" "$(sh "$CORAX" version)"

sh "$CORAX" bogus >/dev/null 2>&1
is "an unknown subcommand exits 1" 1 "$?"

sh "$CORAX" help >/dev/null 2>&1
is "help exits 0" 0 "$?"

reset
env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" sh "$CORAX" send 'deploy done' >/dev/null 2>&1
is "send delivers an arbitrary message" 1 "$(grep -c 'deploy done' "$WORK/sink")"

reset 'CORAX_ENABLED=0'
env CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" sh "$CORAX" send 'nope' >/dev/null 2>&1
is "send respects the kill switch" 0 "$(grep -c 'nope' "$WORK/sink" || true)"

# --- result ------------------------------------------------------------------

printf '\n%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
