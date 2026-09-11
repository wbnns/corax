# Security

## Reporting a vulnerability

Please use GitHub's private advisory form on this repository rather than a
public issue. corax is a young project maintained by one person, so there is no
formal SLA, but I will read it quickly.

## What is worth reporting

corax handles a credential and edits a file Claude Code executes from, so the
interesting surface is small and specific:

- **Credential exposure.** The bot token is passed to curl through a config on
  stdin so it never reaches argv. Anything that puts it in `ps`, a log, a
  crash dump, or `corax doctor` output is a real finding.
- **Command injection through payload data.** Folder names, branch names and
  message text come from outside and can be influenced by a repository you
  cloned. They are stripped of control characters, truncated, and passed as
  arguments rather than interpolated into a shell string. A way around that is
  a real finding.
- **Settings file corruption.** `corax hooks install` merges into
  `~/.claude/settings.json`, which may be a symlink into a dotfiles repo and may
  hold other tools' hooks. Anything that clobbers another tool's entries, or
  writes a file Claude Code then refuses to parse, is a real finding.
- **The config file** is written mode 600. A path where it is not is a finding.
- **Data leaving the machine that the README does not list.** corax sends four
  strings and nothing else. A path that sends more is a finding.

## What is not a vulnerability

- The `command` transport runs a command you configured, with your privileges.
  That is the feature.
- ntfy topics are readable by anyone who knows the topic name. This is how ntfy
  works, which is why `corax init` generates a random one and says so.
- The folder and branch names reaching your chosen transport. That is the point
  of the tool, and `.no-corax` and `CORAX_REDACT=1` exist for when it is not.
