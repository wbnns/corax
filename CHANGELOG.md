# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/wbnns/corax/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/wbnns/corax/releases/tag/v0.1.0
