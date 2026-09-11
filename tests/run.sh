#!/bin/sh
# corax test suite. Plain POSIX sh on purpose: no bats, no shunit2, nothing to
# install. It must run on a bare server and on a Mac without a single dependency
# that corax itself does not already need.
#
# Usage: tests/run.sh
set -u

# shellcheck disable=SC1007  # `CDPATH= cd` is a deliberate env prefix, not an
# empty assignment: it stops cd from printing a path when CDPATH is set.
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
is() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi
}

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
# Pin the branch name: git's default is main on some distros and master on
# others, and Alpine picks master, which used to fail this test on CI only.
( cd "$GITREPO" && git init -q && git symbolic-ref HEAD refs/heads/main &&
  git config user.email t@t && git config user.name t &&
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
            'elicitation_dialog|has a dialog waiting for an answer' \
            'elicitation_url_dialog|has a dialog waiting for an answer' \
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
backdate d2b turn 30
is "a waiting dialog is never swallowed by a turn message either" \
   1 "$(count "$(payload Notification elicitation_dialog /tmp d2b)")"

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

reset 'CORAX_STOP=0'
is "CORAX_STOP=0 also silences a finished background agent" \
   0 "$(count "$(payload Notification agent_completed /tmp g5b)")"

reset 'CORAX_STOP=0'
is "CORAX_STOP=0 leaves a waiting dialog alone" \
   1 "$(count "$(payload Notification elicitation_dialog /tmp g5c)")"

reset 'CORAX_STOP=0'
is "CORAX_STOP=0 leaves a waiting subagent alone" \
   1 "$(count "$(payload Notification agent_needs_input /tmp g5d)")"

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
# Assert the folder field, not the whole line: the hostname is also a field and
# CI runners have very long ones, so a whole-line budget tests the wrong thing.
got=$(send "$(payload Notification permission_prompt "$WORK/$LONG" h2)" | head -1)
folder=${got##* · }
len=$(printf '%s' "$folder" | wc -c | tr -d ' ')
if [ "$len" -le 64 ] && [ "$len" -lt "$(printf '%s' "$LONG" | wc -c | tr -d ' ')" ]; then
  ok "a very long folder name is truncated to 64"
else
  bad "a very long folder name is truncated to 64" "<=64 bytes, shorter than the input" "$len bytes"
fi

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

# --- network transports ------------------------------------------------------
# The command sink cannot see a request body, so the transports that actually
# POST have never been covered. They get a second double: a stub curl on PATH
# that records argv, whatever config it is handed on stdin, and the -d body,
# each in its own file. Nothing touches the network.
#
# It has to be driven through `corax send`. Hook mode rewrites PATH to put the
# system directories first, so a stub placed there would be shadowed by the real
# curl and every one of these tests would try to reach the internet.

printf '\nnetwork transports\n'

mkdir -p "$WORK/bin"
cat > "$WORK/bin/curl" <<'CURL'
#!/bin/sh
_prev=
for _a in "$@"; do
  [ "$_prev" = "-d" ] && printf '%s' "$_a" > "$WIRE/body"
  printf '%s\n' "$_a" >> "$WIRE/argv"
  _prev=$_a
done
cat >> "$WIRE/stdin"
CURL
chmod +x "$WORK/bin/curl"

# wire <transport> <text> [config lines...]
# Leaves $WIRE/argv, $WIRE/stdin and $WIRE/body for the assertions to read.
WIRE="$WORK/wire"
wire() {
  rm -rf "$WIRE"; mkdir -p "$WIRE"
  : > "$WIRE/argv"; : > "$WIRE/stdin"; : > "$WIRE/body"
  _wt=$1; _wx=$2; shift 2
  {
    printf 'CORAX_TRANSPORT=%s\n' "$_wt"
    for _wl in "$@"; do printf '%s\n' "$_wl"; done
  } > "$WORK/config"
  env CORAX_CONFIG="$WORK/config" WIRE="$WIRE" \
    PATH="$WORK/bin:$PATH" sh "$CORAX" send "$_wx" >/dev/null 2>&1
}

# saw <file> <pattern> -> 1 when the pattern is there, 0 when it is not
saw() {
  if grep -q "$2" "$WIRE/$1" 2>/dev/null; then echo 1; else echo 0; fi
}

SLACK_URL='https://hooks.slack.com/services/T00/B00/sEcReT'
DISCORD_URL='https://discord.com/api/webhooks/123/sEcReT'

wire slack hi "CORAX_SLACK_WEBHOOK_URL=$SLACK_URL"
is "slack sends the text key" 1 "$(saw body '"text"')"
is "slack does not send discord's key" 0 "$(saw body '"content"')"

wire discord hi "CORAX_DISCORD_WEBHOOK_URL=$DISCORD_URL"
is "discord sends the content key" 1 "$(saw body '"content"')"
is "discord does not send slack's key" 0 "$(saw body '"text"')"

# The invariant the generic webhook used to break. A webhook url carries its own
# secret in the path, so it is a credential and must never reach argv, where any
# other user on the box can read it out of ps.
wire slack hi "CORAX_SLACK_WEBHOOK_URL=$SLACK_URL"
is "slack keeps its url out of argv" 0 "$(saw argv sEcReT)"
is "slack passes its url on stdin" 1 "$(saw stdin sEcReT)"

wire discord hi "CORAX_DISCORD_WEBHOOK_URL=$DISCORD_URL"
is "discord keeps its url out of argv" 0 "$(saw argv sEcReT)"
is "discord passes its url on stdin" 1 "$(saw stdin sEcReT)"

wire webhook hi "CORAX_WEBHOOK_URL=$SLACK_URL"
is "the generic webhook keeps its url out of argv" 0 "$(saw argv sEcReT)"
is "the generic webhook passes its url on stdin" 1 "$(saw stdin sEcReT)"

wire twilio hi \
  'CORAX_TWILIO_SID=AC123' 'CORAX_TWILIO_TOKEN=tOkEnSeCrEt' \
  'CORAX_TWILIO_FROM=+15550001111' 'CORAX_TWILIO_TO=+15550002222'
is "twilio sends the message body" 1 "$(saw argv '^Body=')"
is "twilio sends from" 1 "$(saw argv '^From=+15550001111$')"
is "twilio sends to" 1 "$(saw argv '^To=+15550002222$')"
is "twilio keeps the auth token out of argv" 0 "$(saw argv tOkEnSeCrEt)"
is "twilio passes the auth token on stdin" 1 "$(saw stdin tOkEnSeCrEt)"

# Discord renders markdown in content, and a folder or branch name is exactly
# the kind of string that carries an underscore.
# shellcheck disable=SC2016  # the backticks are literal input, not a command
wire discord 'feat_x `tick` *star*' "CORAX_DISCORD_WEBHOOK_URL=$DISCORD_URL"
is "discord escapes an underscore" 1 "$(saw body 'feat\\\\_x')"
# shellcheck disable=SC2016  # likewise: this is a grep pattern for a backtick
is "discord escapes a backtick" 1 "$(saw body '\\\\`tick\\\\`')"
is "discord escapes an asterisk" 1 "$(saw body '\\\\\*star\\\\\*')"

wire slack 'a & b < c > d' "CORAX_SLACK_WEBHOOK_URL=$SLACK_URL"
is "slack escapes the three characters it reserves" 1 \
   "$(saw body 'a &amp; b &lt; c &gt; d')"

# A quote or a backslash in a branch name must not be able to break the body.
# Both code paths get the same input: jq when it is there, and the hand-rolled
# escaper when it is not. CORAX_JQ pointed at nothing forces the second, which
# is the only way to reach it on a machine that has jq installed.
QUOTED='he said "hi" and \ too'

wire slack "$QUOTED" "CORAX_SLACK_WEBHOOK_URL=$SLACK_URL" "CORAX_JQ=$WORK/no-such-jq"
is "the no-jq fallback escapes a quote" 1 "$(saw body 'said \\"hi\\"')"
is "the no-jq fallback escapes a backslash" 1 "$(saw body 'and \\\\ too')"
is "the no-jq fallback still closes the object" 1 "$(saw body '}$')"

if command -v jq >/dev/null 2>&1; then
  wire slack "$QUOTED" "CORAX_SLACK_WEBHOOK_URL=$SLACK_URL" "CORAX_JQ=$(command -v jq)"
  if jq -e . "$WIRE/body" >/dev/null 2>&1; then
    ok "the jq path produces valid json for the same input"
  else
    bad "the jq path produces valid json for the same input" "valid json" "$(cat "$WIRE/body")"
  fi
  is "the jq path round-trips the text unchanged" "[corax] $HOST: $QUOTED" \
     "$(jq -r '.text' "$WIRE/body" 2>/dev/null)"
else
  ok "the jq path (skipped, no jq on this machine)"
  ok "the jq round trip (skipped, no jq on this machine)"
fi

# Missing configuration is a silent no-op, never an error and never a request.
for _t in slack discord twilio webhook; do
  wire "$_t" hi
  is "$_t with no credentials makes no request" 0 \
     "$(wc -c < "$WIRE/argv" | tr -d ' ')"
done

# Every new key has to be in the allowlist or /corax:setup cannot write it, and
# every credential has to be in the redaction list or `config show` prints it.
: > "$WORK/config"
for _k in CORAX_SLACK_WEBHOOK_URL CORAX_DISCORD_WEBHOOK_URL \
          CORAX_TWILIO_SID CORAX_TWILIO_TOKEN CORAX_TWILIO_FROM CORAX_TWILIO_TO \
          CORAX_HEARTBEAT_WARN_HOURS; do
  env CORAX_CONFIG="$WORK/config" sh "$CORAX" config set "$_k" sEcReT >/dev/null 2>&1
  is "config set accepts $_k" 0 "$?"
done
shown=$(env CORAX_CONFIG="$WORK/config" sh "$CORAX" config show 2>/dev/null)
for _k in CORAX_SLACK_WEBHOOK_URL CORAX_DISCORD_WEBHOOK_URL CORAX_TWILIO_TOKEN; do
  is "config show redacts $_k" 1 "$(printf '%s' "$shown" | grep -c "^$_k=<redacted>$")"
done
is "config show leaves a non-secret alone" 1 \
   "$(printf '%s' "$shown" | grep -c '^CORAX_TWILIO_FROM=sEcReT$')"

# --- settings detection ------------------------------------------------------
# doctor decides whether hooks are registered in settings.json. A plugin install
# writes "corax@corax" into enabledPlugins and extraKnownMarketplaces, so a plain
# grep for the word reports every plugin user as a broken double install.

printf '\nsettings detection\n'

mkdir -p "$WORK/home/.claude"
cat > "$WORK/home/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": { "corax@corax": true },
  "extraKnownMarketplaces": { "corax": { "source": { "source": "github", "repo": "wbnns/corax" } } },
  "hooks": {
    "Notification": [
      { "matcher": "idle_prompt",
        "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/some-other-tool.sh" }] }
    ]
  }
}
JSON
HOME="$WORK/home" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'BOTH as a plugin' "$WORK/doc"; then
  bad "a plugin install alone is not a double install" "no BOTH warning" "warned"
else
  ok "a plugin install alone is not a double install"
fi

# ...but a real corax hook command in the same file must still be detected.
cat > "$WORK/home/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "Stop": [ { "hooks": [{ "type": "command", "command": "sh \"$HOME/.local/bin/corax\"" }] } ]
  }
}
JSON
HOME="$WORK/home" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'registered in' "$WORK/doc"; then
  ok "a corax hook command in settings.json is detected"
else
  bad "a corax hook command in settings.json is detected" "registered in ..." "$(grep -c . "$WORK/doc") lines, no match"
fi

# The same two checks again with python3 and jq hidden, so the pure-grep fallback
# is exercised everywhere rather than only on hosts that happen to lack both.
mkdir -p "$WORK/thinbin"
for _c in sh cat grep sed cut tr head wc id hostname date find basename dirname \
          chmod mkdir rm ls curl printf; do
  _p=$(command -v "$_c" 2>/dev/null) || continue
  [ -x "$_p" ] && ln -sf "$_p" "$WORK/thinbin/$_c"
done

cat > "$WORK/home/.claude/settings.json" <<'JSON'
{
  "enabledPlugins": { "corax@corax": true },
  "hooks": { "Notification": [ { "matcher": "idle_prompt",
    "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/other-tool.sh" }] } ] }
}
JSON
env -i HOME="$WORK/home" PATH="$WORK/thinbin" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'BOTH as a plugin' "$WORK/doc"; then
  bad "no-parser fallback: a plugin install alone is not a double install" "no warning" "warned"
else
  ok "no-parser fallback: a plugin install alone is not a double install"
fi

cat > "$WORK/home/.claude/settings.json" <<'JSON'
{
  "hooks": { "Stop": [ { "hooks": [{ "type": "command", "command": "sh \"$HOME/.local/bin/corax\"" }] } ] }
}
JSON
env -i HOME="$WORK/home" PATH="$WORK/thinbin" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'registered in' "$WORK/doc"; then
  ok "no-parser fallback: an escaped-quote corax command is still detected"
else
  bad "no-parser fallback: an escaped-quote corax command is still detected" "registered in ..." "no match"
fi

# --- heartbeat ---------------------------------------------------------------
# The question configuration cannot answer: did Claude Code actually call us?
# Everything else can be green while corax is deaf, because hooks load at session
# start and a session older than the install never got them.

printf '\nheartbeat\n'

hb="$WORK/home/.local/state/corax/last-hook"

# It must record even when corax decides to send nothing, or it would only prove
# that a message went out, which is the thing we already knew.
for case_ in 'normal|' \
             'muted|CORAX_ENABLED=0' \
             'stop silenced|CORAX_STOP=0'; do
  label=${case_%%|*}; extra=${case_#*|}
  rm -rf "$WORK/home/.local"
  if [ -n "$extra" ]; then reset "$extra"; else reset; fi
  printf '%s' "$(payload Stop '' /tmp hb-$$)" | env \
    HOME="$WORK/home" CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" \
    TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
  if [ -r "$hb" ]; then ok "records a hook that sent nothing: $label"
  else bad "records a hook that sent nothing: $label" "a heartbeat file" "none"; fi
done

rm -rf "$WORK/home/.local"
printf '%s' "$(payload Stop '' /tmp hb2)" | env \
  HOME="$WORK/home" CORAX_CONFIG=/nonexistent TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
if [ -r "$hb" ]; then ok "records a hook with no config at all"
else bad "records a hook with no config at all" "a heartbeat file" "none"; fi

is "records which event fired" "Stop" "$(cut -d' ' -f2 "$hb")"

# It must survive a swept TMPDIR: the dedupe stamps live there and losing one
# costs a duplicate message, but losing the heartbeat reads as corax being deaf.
rm -rf "$WORK/state"
if [ -r "$hb" ]; then ok "survives a swept TMPDIR"
else bad "survives a swept TMPDIR" "still there" "gone"; fi

rm -rf "$WORK/home/.local"
reset
HOME="$WORK/home" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'no hook has ever fired' "$WORK/doc"; then
  ok "doctor says so when no hook has ever fired"
else
  bad "doctor says so when no hook has ever fired" "never fired warning" "absent"
fi

mkdir -p "$WORK/home/.local/state/corax"
printf '%s Stop\n' "$(( $(date +%s) - 108000 ))" > "$hb"
HOME="$WORK/home" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'no hook for 30 hours' "$WORK/doc"; then
  ok "doctor warns on a stale heartbeat and names the age"
else
  bad "doctor warns on a stale heartbeat and names the age" "no hook for 30 hours" \
      "$(grep heartbeat "$WORK/doc" | head -1)"
fi

printf '%s Notification\n' "$(date +%s)" > "$hb"
HOME="$WORK/home" sh "$CORAX" doctor >"$WORK/doc" 2>&1 || true
if grep -q 'last hook .* ago (Notification)' "$WORK/doc"; then
  ok "doctor reports a fresh heartbeat with its event"
else
  bad "doctor reports a fresh heartbeat with its event" "last hook N ago (Notification)" \
      "$(grep heartbeat "$WORK/doc" | head -1)"
fi

# --- housekeeping ------------------------------------------------------------
# Nothing corax writes may grow without bound. Two files behave differently and
# both need proving.

printf '\nhousekeeping\n'

# The heartbeat is overwritten, not appended, so it is one line forever.
rm -rf "$WORK/home/.local"
reset
i=0
while [ "$i" -lt 200 ]; do
  printf '%s' "$(payload Stop '' /tmp "grow$i")" | env \
    HOME="$WORK/home" CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" \
    TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
  i=$(( i + 1 ))
done
is "the heartbeat stays one line after 200 hooks" 1 \
   "$(wc -l < "$WORK/home/.local/state/corax/last-hook" | tr -d ' ')"

# The dedupe stamps are one small file per session, swept after a day.
# Count matching files with a glob, not `ls | grep`: filenames are not a text
# stream, and shellcheck is right to object.
countglob() {
  _n=0
  for _f in $1; do [ -e "$_f" ] && _n=$(( _n + 1 )); done
  printf '%s' "$_n"
}

sd="$WORK/state/corax-$(id -u 2>/dev/null || echo u)"
mkdir -p "$sd"
i=0
while [ "$i" -lt 20 ]; do
  : > "$sd/stale$i.turn"
  # A fixed past date, not date arithmetic. BSD wants -v-2d, GNU wants
  # -d "2 days ago", and busybox date accepts neither, which is how this test
  # passed on a Mac and failed on Alpine.
  touch -t 202001010000 "$sd/stale$i.turn" 2>/dev/null
  i=$(( i + 1 ))
done
printf '%s' "$(date +%s)" > "$sd/recent.turn"
printf '%s' "$(payload Stop '' /tmp sweeptrigger)" | env \
  HOME="$WORK/home" CORAX_CONFIG="$WORK/config" CORAX_SINK="$WORK/sink" \
  TMPDIR="$WORK/state" sh "$CORAX" >/dev/null 2>&1
is "day-old dedupe stamps are swept" 0 "$(countglob "$sd/stale*")"
is "recent dedupe stamps are kept" 1 "$(countglob "$sd/recent*")"

# --- wiring ------------------------------------------------------------------
# A reason the code can produce but no matcher delivers is dead code. This is the
# check that would have caught the three that shipped unregistered in 0.1.x.

printf '\nwiring\n'

# Extract the notification types the reason table names, minus the hook-event
# names, which are not notification types and have no matcher.
sed -n '/case "${_ntype:-\$_event}" in/,/^  esac/p' "$CORAX" \
  | sed -n 's/^[[:space:]]*\([a-z_|]\{1,\}\)).*/\1/p' \
  | tr '|' '\n' | grep -v '^Stop$' | grep . | sort -u > "$WORK/handled"
sed -n 's/.*"matcher": "\([a-z_]*\)".*/\1/p' "$ROOT/hooks/hooks.json" | sort -u > "$WORK/registered"
sed -n '/^plan = \[/,/^        ("Stop", None)\]/p' "$CORAX" \
  | sed -n 's/.*"Notification", "\([a-z_]*\)".*/\1/p' | sort -u > "$WORK/installer"

# comm, not process substitution: this file has to run under dash and busybox.
missing=$(comm -23 "$WORK/handled" "$WORK/registered")
if [ -s "$WORK/handled" ] && [ -z "$missing" ]; then
  ok "every notification type the code handles is registered by the plugin"
else
  bad "every notification type the code handles is registered by the plugin" \
      "none unregistered, from a non-empty list" \
      "handled=$(tr '\n' ' ' < "$WORK/handled")unregistered=$(printf '%s' "$missing" | tr '\n' ' ')"
fi

if [ -s "$WORK/registered" ] && cmp -s "$WORK/registered" "$WORK/installer"; then
  ok "the settings.json installer registers the same set as the plugin"
else
  bad "the settings.json installer registers the same set as the plugin" \
      "plugin: $(tr '\n' ' ' < "$WORK/registered")" \
      "installer: $(tr '\n' ' ' < "$WORK/installer")"
fi

# --- result ------------------------------------------------------------------

printf '\n%s passed, %s failed\n\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
