# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-09-11

### Added

- Three transports: **slack**, **discord** and **twilio**. Slack and Discord are
  incoming webhooks, so setup is one URL and no bot. Twilio sends SMS, or
  WhatsApp when both numbers carry a `whatsapp:` prefix.

  Slack already worked through the generic `webhook` transport by accident,
  since that POSTs `{"text": ...}` and Slack happens to want exactly that.
  Discord did not: it wants `{"content": ...}` and rejects a body without it,
  so a Discord URL in `CORAX_WEBHOOK_URL` failed silently. Both are now their
  own transport, which is what gets them a menu entry, a URL sanity check, and
  a redacted config.

- `corax_escape`, because Discord renders markdown in a message. A folder called
  `my_project` was arriving as *myproject* in italics. Telegram never needed this
  since corax does not send `parse_mode`, and SMS has no formatting at all.

- `corax init` checks Twilio credentials against the API before writing them,
  the way it already checked a Telegram token. A typo now fails at setup rather
  than silently at three in the morning.

- Choosing Twilio writes `CORAX_STOP=0`. It is the only transport that costs
  money, and a turn ends on every exchange, so the default would have been about
  a hundred billed texts a day. Anything that actually blocks you still sends.

- Coverage for the transports that make network requests. They had none: the
  test suite used the `command` transport as its sink, and a sink cannot see a
  request body. A stub `curl` on `PATH` now records argv, stdin and the body, so
  the escaping and the credential handling are both asserted. Still no network.

### Fixed

- **The generic `webhook` transport put its URL on argv**, where any other user
  on the machine could read it out of `ps`. A webhook URL carries its own secret
  in the path, so it is a credential exactly like a bot token, and the rule that
  covers bot tokens should always have covered it. All JSON transports now share
  one sender that passes the URL through a curl config on stdin.
- `CORAX_HEARTBEAT_WARN_HOURS` was documented in the README but rejected by
  `corax config set`, so `/corax:setup` could not write it.
- `CORAX_JQ` pointed at something that is not executable now means "there is no
  jq" rather than "go and find a different one". A wrong override was being
  silently ignored, and the no-parser path could not be tested on a machine that
  has jq installed.

## [0.3.0] - 2026-09-11

### Added

- A heartbeat. corax records a timestamp and the event name on every hook
  invocation, before any guard, so the record exists even when it goes on to send
  nothing. `doctor` reports it: `last hook 4 minutes ago (Notification)`, or a
  warning when nothing has fired for a day, or when nothing has ever fired.
- `CORAX_HEARTBEAT_WARN_HOURS`, default 24.
- Tests that nothing corax writes grows without bound: the heartbeat is
  overwritten rather than appended, so it is one line after two hundred hooks,
  and the day-old dedupe stamps really are swept. The sweep had shipped since
  0.1.0 without a test.

  This exists because `doctor` could report every check green while corax was
  delivering nothing at all. Hooks load when a session starts, so any session
  already running when you install corax never gets them, and configuration
  cannot see that. The heartbeat is the only thing that can distinguish "set up
  correctly" from "actually being called".

  It lives in `~/.local/state/corax/`, not the temp directory that holds the
  dedupe stamps. Losing a stamp costs one duplicate message; losing the heartbeat
  would read as corax having gone deaf, and macOS sweeps `/var/folders` while
  Linux clears `/tmp` on boot.

## [0.2.0] - 2026-09-11

### Added

- Three notification types now actually reach you. `elicitation_dialog` and
  `elicitation_url_dialog` say `has a dialog waiting for an answer`, and
  `agent_completed` says `finished a background agent`. All three had reasons
  written for them since 0.1.0, but no matcher registered them, so the hook was
  never called and the branches were dead. A dialog waiting on an answer blocks
  you exactly the way a permission prompt does, which is why the two elicitation
  types share the permission dedupe window rather than the turn one.
- A wiring test that fails when the reason table names a notification type the
  plugin does not register, or when the plugin and the settings.json installer
  register different sets. This is the check that would have caught the above.

### Changed

- `CORAX_STOP=0` now means "drop the completion notices" rather than "drop the
  Stop event". It silences a finished turn and a finished background agent, and
  leaves everything that is waiting on an answer.

## [0.1.2] - 2026-09-11

### Fixed

- On a machine with neither python3 nor jq, `doctor` could not see a corax hook
  in `settings.json` and reported that hooks were not registered at all. The
  pure-grep fallback modelled JSON string escaping with a `[^"]*` run, which
  stops at the first `\"`, and the command corax installs is
  `sh \"$HOME/.local/bin/corax\"`. It now requires only the command context.
  Caught by the busybox CI job, which is the one host with no parser available.

### Changed

- The two settings-detection tests now also run with python3 and jq hidden, so
  the fallback is exercised on every platform rather than only where both
  parsers happen to be missing.

## [0.1.1] - 2026-09-11

### Fixed

- `doctor` reported a double install for anyone who installed the plugin. It
  looked for the word corax anywhere in `settings.json`, and a plugin install
  writes `corax@corax` into `enabledPlugins` and `extraKnownMarketplaces`. It now
  looks for a corax command inside the hooks structure specifically, so the
  warning fires only when hooks really are registered twice.

## [0.1.0] - 2026-09-11

First release.

### Added

- A hook for Claude Code that sends a message when a session needs attention,
  naming the machine, the folder and the branch. Handles the permission prompt,
  the idle prompt, a waiting subagent, and the end of a turn.
- Four transports: Telegram, ntfy, a generic webhook, and an arbitrary command.
- `corax init`, which for Telegram discovers your chat id by waiting for you to
  message the bot, so you never have to go and find it.
- `corax doctor`, which checks every link in the chain and prints the message it
  would send. It also catches the case where corax is installed both as a plugin
  and in `settings.json`, which would otherwise send you everything twice.
- Installation as a Claude Code plugin, which registers the hooks without
  touching `~/.claude/settings.json` at all.
- `corax send`, for notifying yourself from your own scripts.
- Two deduplication windows. Turn events share one of 90 seconds, because Claude
  Code raises its idle notification about 60 seconds after a turn ends and a
  shorter window double-sends. Permission events keep their own of 20 seconds,
  so a turn message can never swallow the alert that actually blocks work.
- Privacy controls: a `.no-corax` file per project, `CORAX_REDACT=1` to drop the
  folder and branch, and `corax off` for the whole machine.

[Unreleased]: https://github.com/wbnns/corax/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/wbnns/corax/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/wbnns/corax/compare/v0.1.2...v0.2.0
[0.1.2]: https://github.com/wbnns/corax/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/wbnns/corax/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/wbnns/corax/releases/tag/v0.1.0
