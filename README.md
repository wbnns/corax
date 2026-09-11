![corax](https://raw.githubusercontent.com/wbnns/corax/main/assets/corax-og.jpg)

# corax

**corax watches your agents and swarms from the terminal, and lets you and your
team know when one needs you, wherever that reaches you.**

In Greek, corax is the raven. Apollo kept one as an omen bird: it flew out, saw
what people could not, and came back to tell him.

Agents stop and wait. One wants permission to run a command or a tool, another
wants your input before it goes on, a third has finished and the result is
sitting there unread. With one agent in one terminal in front of you, you
notice. With a laptop, a desktop and two boxes you reach over a VPN, you do not.

A desktop app helps only while it is open, and only on the machine you happen to
be sitting at. It does not carry the part you actually need: which machine
stopped, which folder and branch it was working in, and what kind of answer it
wants. A terminal bell has the same problem, and rings on the machine you are
not looking at.

corax sends you the missing context instead:

```
[corax] zulu · a2ciple.pt · main
needs permission to run a tool
```

That goes wherever you already look: Telegram, Slack, Discord, ntfy, an SMS
through Twilio, any webhook, or a command you supply.

Point it at a channel your team shares and it works for a swarm as well as for
one person. Everyone sees which agent is blocked and on what. Someone reacts to
the message to say they have it, and nobody else goes looking. corax does not
run that process for you. It puts the request somewhere people already are, and
`corax send 'deploy done'` pushes anything else you want them to know through
the same transport.

Claude Code is the agent corax speaks today, and it installs there as a plugin.
The parsing is the only part specific to it. The identity line, the
deduplication and the transports are not, so a second agent is a new parser
rather than a rewrite.

The alternatives get this wrong in predictable ways. A raw `curl` in your
settings file has no deduplication, puts your bot token in `ps` where every
other user on the box can read it, and breaks the first time a branch name
contains a quote. Desktop notifier tools are still, definitionally, local.

Most of what is here is not the sending. It is the handful of things that are
wrong on the first attempt, and stay wrong quietly:

- Claude Code raises its idle notification about sixty seconds after a turn
  ends, so any deduplication window shorter than that sends you two messages for
  one event.
- A "turn finished" message must not share a deduplication window with a
  permission request. If it does, a permission prompt arriving shortly after a
  turn gets swallowed, and that is the one message that actually blocks work.
- Hook entries merge across settings files rather than replacing each other, so
  installing a notifier without removing the old banner gives you both.
- Hook output on stdout is fed back into the model's context on some events.

## Install

Inside Claude Code, as a plugin. This registers the hooks for you, so nothing
edits your settings file:

```
/plugin marketplace add wbnns/corax
/plugin install corax@corax
/corax:setup
```

Or on a server, where there is no interactive session to type that into:

```sh
curl -fsSL https://raw.githubusercontent.com/wbnns/corax/main/install.sh | sh
corax init
```

`corax` is one POSIX shell script with no dependency but `curl`. There is no
node, no python, no virtualenv. If you would rather read it before running it,
it is about eleven hundred lines with the reasoning in the comments, and you can
also `npx @wbnns/corax init` or clone the repo and run `./corax` in place.

## What it tells you about

Two categories. The first is blocking: something is waiting on an answer from
you and nothing moves until you give one.

| | |
| --- | --- |
| Claude wants to run a tool that needs approval | `needs permission to run a tool` |
| A dialog is waiting on you | `has a dialog waiting for an answer` |
| A subagent cannot decide alone | `has a subagent waiting on you` |
| Claude finished a minute ago and you have not typed | `is waiting for your input` |

The second is completion: something finished, nothing is blocked. `CORAX_STOP=0`
drops these and keeps everything above.

| | |
| --- | --- |
| A turn ended | `finished a turn` |
| A background agent ended | `finished a background agent` |

A turn ends on every exchange, not only when you walk away, so it is the chatty
one. If corax is too talkative that is the switch to reach for.

Plus `corax send 'deploy done'` for your own scripts, or for telling the channel
anything else you want it to know. That path has nothing to do with Claude Code.

## Transports

| | Setup | Who else can read it |
| --- | --- | --- |
| ntfy | A topic name. No account. | Anyone who knows the topic, which is why `init` generates a random one |
| telegram | A bot from @BotFather | Telegram, and anyone holding your bot token |
| slack | An incoming webhook URL | Everyone in that channel, and anyone holding the URL |
| discord | An incoming webhook URL | Everyone in that channel, and anyone holding the URL |
| twilio | An account sid, an auth token, and two phone numbers. **Billed per message** | Twilio, and your carrier |
| webhook | A URL. Receives `{"text": "..."}` | Whoever runs the endpoint |
| command | Any command. Gets the message as its one argument | Nobody, unless your command sends it somewhere |

An incoming webhook URL is a password. Anyone holding it can post to that
channel, so corax keeps it out of `ps` and redacts it in `corax config show`.

Twilio is the only one that costs money, and a turn ends on every exchange, so
left alone it would be a hundred billed texts in a working day. `corax init`
sets `CORAX_STOP=0` for you when you pick it, which drops the turn-finished
pings and keeps everything that actually blocks you. Put `whatsapp:` in front of
both numbers to send WhatsApp instead of SMS.

`corax init` walks you through whichever you pick. For Telegram it does the part
everyone gets stuck on: after you paste the token, it waits for you to message
the bot and reads your chat id back out, so you never go looking for it. For
Slack and Discord it says so when a URL does not look like one of theirs, and
for Twilio it checks the sid and token against the API before writing them, so a
typo fails at setup rather than silently at three in the morning.

## Using it

```sh
corax doctor          # check every link in the chain, and print what it would send
corax test            # send one message of each kind
corax off             # silence this machine
corax on              # unsilence it
corax send 'deploy done'   # for your own scripts, nothing to do with Claude Code
```

If you installed the plugin, the hooks are already registered and you can ignore
the rest of this. If you installed the script on its own:

```sh
corax hooks install   # add the hooks to ~/.claude/settings.json
corax hooks uninstall # take them out again, leaving other tools' hooks alone
corax hooks show      # print the hooks block
```

And for setting things without a prompt, which is how the plugin's `/corax:setup`
drives it:

```sh
corax config set CORAX_TRANSPORT ntfy
corax config show     # secrets redacted
corax config path
corax telegram-chat TOKEN   # your chat id, once you have messaged the bot
```

`doctor` answers the one question configuration cannot. corax writes a heartbeat
on every hook invocation, so it can tell you whether Claude Code has actually
called it, not merely whether it is set up correctly. Those are different, and
the difference is the failure you will hit: hooks load when a session starts, so
a session already running when you install corax never gets them, and everything
else looks green while nothing arrives.

```
ok    heartbeat  last hook 4 minutes ago (Notification)
warn  heartbeat  no hook for 30 hours
warn  heartbeat  no hook has ever fired on this machine
```

## Settings

All of it lives in `~/.config/corax/config`, mode 600, written by `corax init`.
It is plain `KEY=value` sourced by the shell, so you can edit it by hand.

| Key | Default | |
| --- | --- | --- |
| `CORAX_TRANSPORT` | | `telegram`, `ntfy`, `slack`, `discord`, `twilio`, `webhook` or `command` |
| `CORAX_TELEGRAM_TOKEN` | | From @BotFather |
| `CORAX_TELEGRAM_CHAT` | | Found for you by `corax init` |
| `CORAX_NTFY_TOPIC` | | Pick something unguessable; `init` generates one |
| `CORAX_NTFY_URL` | `https://ntfy.sh` | Your own server, if you run one |
| `CORAX_SLACK_WEBHOOK_URL` | | From a Slack app with Incoming Webhooks on |
| `CORAX_DISCORD_WEBHOOK_URL` | | Channel settings, Integrations, New Webhook |
| `CORAX_TWILIO_SID` | | Account sid, from the Twilio console |
| `CORAX_TWILIO_TOKEN` | | Auth token, from the same place |
| `CORAX_TWILIO_FROM` | | Your Twilio number, E.164. `whatsapp:` prefix for WhatsApp |
| `CORAX_TWILIO_TO` | | Your phone, same format |
| `CORAX_WEBHOOK_URL` | | Receives `{"text": "..."}` |
| `CORAX_COMMAND` | | Gets the message as its one argument |
| `CORAX_ENABLED` | `1` | `0` silences everything. `corax off` sets this |
| `CORAX_STOP` | `1` | `0` drops the completion notices, keeps anything waiting on you |
| `CORAX_REDACT` | `0` | `1` sends the host and reason but no folder or branch |
| `CORAX_TURN_WINDOW` | `90` | Dedupe window for turn events, seconds |
| `CORAX_PERM_WINDOW` | `20` | And for anything blocking, which gets its own |
| `CORAX_HEARTBEAT_WARN_HOURS` | `24` | When `doctor` starts calling the heartbeat stale |
| `CORAX_TIMEOUT` | `8` | Seconds before a send is abandoned |

Every one of them can also be set in the environment, which is how the test
suite drives corax without touching your real configuration.

## What it leaves on disk

Two files, neither of which grows without bound.

| | Where | Size |
| --- | --- | --- |
| Heartbeat | `~/.local/state/corax/last-hook` | One line, overwritten every time. 16 bytes, forever. |
| Dedupe stamps | `$TMPDIR/corax-<uid>/` | One ten-byte file per session, swept after a day. |

Nothing is appended to, so there is no log to rotate. The stamps are the only
thing that accumulates, and they are cleaned on the next hook after they age out.

## Privacy

corax sends four strings and no others: your short hostname, one directory name,
one branch name, and a reason it picks from a fixed list it writes itself.

It never sends file contents, full paths, your prompts, Claude's replies,
transcripts, environment variables, or session ids. There is no telemetry, no
version check, and no analytics. It makes exactly one network request per
notification, to the endpoint you configured, and none at any other time.

Three ways to send less:

- Put an empty `.no-corax` file in a repository and that project never notifies.
  Useful when the branch names carry a client's name.
- Set `CORAX_REDACT=1` to send the host and the reason but drop the folder and
  the branch.
- Use the `command` transport, where nothing leaves the machine unless the
  command you wrote sends it.

Your credentials live in `~/.config/corax/config` at mode 600 and are never
passed on a command line, so they do not appear in `ps` to other users on a
shared box. That covers the Twilio auth token and the Slack and Discord webhook
URLs as well as the Telegram bot token: a webhook URL carries its own secret in
the path, which makes it a password and not an address.

## What it is not

It does not read your code, summarise anything, or call a model. It is a hook
that notices a handful of events and sends you two lines of text.

Today it speaks Claude Code and nothing else. The event parsing is specific to
Claude Code's hook payloads, and that specificity is the whole point: a generic
notifier would not know that an idle prompt arrives a minute after the turn it
belongs to, or that a permission request must never share a deduplication window
with a finished turn. Another agent is a new parser, not a rewrite.

## Local development

```sh
bin/check
```

That runs everything CI runs: shell syntax under `sh`, `bash` and `dash`, JSON
validation, version agreement across the script and the manifests, shellcheck if
you have it, and the test suite. The tests are plain POSIX shell with no
framework to install, and they use a fake transport that writes to a file, so
nothing touches the network.

## Contributing

Issues and PRs welcome. Please run `bin/check` before opening one, and see
[CONTRIBUTING.md](./CONTRIBUTING.md). Security reports go through
[SECURITY.md](./SECURITY.md) rather than a public issue.

## License

MIT. See [LICENSE](./LICENSE).

## A note from the creator

Hey, it's wbnns :) just wanted to reach out and say hi!

I wrote this because I kept walking back to a laptop to find a session that had
been sitting on a permission prompt for forty minutes. If it misses something it
should have caught, or wakes you when it should have stayed quiet, I want to
know which event and which machine. The deduplication windows in particular are
tuned to how I work, and I would rather hear that they are wrong for you than
guess.

Say hi on **[Telegram](https://t.me/wbnns)**, **[X](https://x.com/wbnns)**, or
email **[hello@wbnns.com](mailto:hello@wbnns.com)**.
