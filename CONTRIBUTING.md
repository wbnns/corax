# Contributing to corax

## Running it locally

```sh
git clone https://github.com/wbnns/corax
cd corax
bin/check
```

`bin/check` is the whole gate. It needs nothing installed beyond what corax
itself needs, so it runs on a bare machine. If you have `shellcheck` or `dash`
it uses them; if not it says so and carries on.

To try your change without touching your real setup, point corax at a scratch
config:

```sh
CORAX_CONFIG=/tmp/corax-test corax config set CORAX_TRANSPORT command
CORAX_CONFIG=/tmp/corax-test corax config set CORAX_COMMAND /bin/echo
printf '{"hook_event_name":"Stop","cwd":"'"$PWD"'","session_id":"x"}' | CORAX_CONFIG=/tmp/corax-test ./corax
```

## Invariants a change must not break

These are not style preferences. Each one is a bug that has already happened
somewhere, and each has a test.

- **Hook mode exits 0 on every path.** A notifier that can fail a session is
  worse than no notifier.
- **Hook mode writes nothing to stdout.** Hook stdout is fed back into the
  model's context on some events.
- **The turn deduplication window stays above 60 seconds.** Claude Code raises
  its idle notification about a minute after a turn ends, so a shorter window
  double-sends.
- **Permission events keep their own deduplication stamp.** If they share the
  turn stamp, a permission prompt arriving after a turn is silently swallowed.
- **No credential ever reaches argv.** Tokens go to curl through a config on
  stdin, so they stay out of `ps`.
- **No payload text is passed through untouched.** Folder names, branch names
  and anything from the payload are stripped of control characters and
  truncated before they go anywhere.
- **Missing configuration is a silent no-op**, never an error.

## Before you open a PR

- **Run `bin/check`.** It should print `all green`.
- **Add a test.** The suite is plain POSIX shell in `tests/run.sh` with no
  framework. A bug fix without a failing-then-passing test is hard to keep.
- **Stay POSIX.** The script runs under `dash` and busybox `ash`, not just
  bash. No `[[`, no arrays, no `local`, no `$'...'`, no `<<<`.
- **Explain why in a comment, not what.** The what is readable from the code.

## Adding a transport

One `case` arm in `corax_send` and one function that takes the message as `$1`,
returns 0 on success, writes nothing to stdout, and bounds itself with
`--max-time`. Add it to the table in the README and to `corax init`.

## License

By contributing you agree that your contributions are licensed under the MIT
License, as in [LICENSE](./LICENSE).
