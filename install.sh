#!/bin/sh
# corax installer, for the headless path: provisioning a server over ssh, where
# there is no interactive Claude Code session to run /plugin install in.
#
#   curl -fsSL https://raw.githubusercontent.com/wbnns/corax/main/install.sh | sh
#
# Puts the script on your PATH and stops. Run `corax init` afterwards to pick a
# transport and register the hooks; nothing is configured without you asking.
set -eu

REPO=${CORAX_REPO:-wbnns/corax}
REF=${CORAX_REF:-main}
PREFIX=${CORAX_PREFIX:-$HOME/.local/bin}
URL="https://raw.githubusercontent.com/$REPO/$REF/corax"

say() { printf '  %s\n' "$*"; }

command -v curl >/dev/null 2>&1 || {
  printf 'corax needs curl, and it is not installed.\n' >&2
  exit 1
}

mkdir -p "$PREFIX"
TMP=$(mktemp "${TMPDIR:-/tmp}/corax.XXXXXX")
trap 'rm -f "$TMP"' EXIT INT TERM

curl -fsSL "$URL" -o "$TMP"
# Refuse a truncated or redirected-to-HTML download rather than installing junk.
head -1 "$TMP" | grep -q '^#!/bin/sh' || {
  printf 'corax: that download does not look like the script. Aborting.\n' >&2
  exit 1
}
sh -n "$TMP" || {
  printf 'corax: the downloaded script does not parse. Aborting.\n' >&2
  exit 1
}

cat "$TMP" > "$PREFIX/corax"
chmod 755 "$PREFIX/corax"

printf '\n'
say "installed $PREFIX/corax  ($("$PREFIX/corax" version))"

case ":$PATH:" in
  *":$PREFIX:"*) ;;
  *)
    say ""
    say "$PREFIX is not on your PATH. Add this to your shell profile:"
    say ""
    say "  export PATH=\"$PREFIX:\$PATH\""
    ;;
esac

say ""
say "next:  corax init"
printf '\n'
