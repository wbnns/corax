# corax

**Claude Code notifications that tell you which machine and which folder is asking.**

The desktop banner works fine until you run Claude Code in more than one place.
Then it tells you that something, somewhere, is waiting. It appears on whichever
machine has focus rather than the one that is blocked, it says nothing about
where, and it is gone in five seconds. If your sessions live on a laptop, a
desktop, and two boxes you reach over a VPN, the banner is close to useless:
the session that stopped to ask you a question is on a machine whose screen you
are not looking at, and often cannot see at all.

corax replaces it with a message that names the machine, the folder and the
branch:

```
[corax] zulu · a2ciple.pt · main
needs permission to run a tool
```

That goes to Telegram, to ntfy, to any webhook, or to a command you supply.

The alternatives get this wrong in predictable ways. A terminal bell notifies
the machine you are not looking at. A raw `curl` in your settings file has no
deduplication, puts your bot token in `ps` where every other user on the box can
read it, and breaks the first time a branch name contains a quote. Desktop
notifier tools are still, definitionally, local.

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
it is about nine hundred lines with the reasoning in the comments, and you can
also `npx corax init` or clone the repo and run `./corax` in place.

## Transports

| | Setup | Who else can read it |
| --- | --- | --- |
| ntfy | A topic name. No account. | Anyone who knows the topic, which is why `init` generates a random one |
| telegram | A bot from @BotFather | Telegram, and anyone holding your bot token |
| webhook | A URL. Receives `{"text": "..."}` | Whoever runs the endpoint |
| command | Any command. Gets the message as its one argument | Nobody, unless your command sends it somewhere |

`corax init` walks you through whichever you pick. For Telegram it does the part
everyone gets stuck on: after you paste the token, it waits for you to message
the bot and reads your chat id back out, so you never go looking for it.

## Using it

```sh
corax doctor          # check every link in the chain, and print what it would send
corax test            # send one message of each kind
corax off             # silence this machine
corax on              # unsilence it
corax send 'deploy done'   # for your own scripts, nothing to do with Claude Code
```

Settings live in `~/.config/corax/config`, mode 600. The ones worth knowing:

```sh
CORAX_STOP=0          # stop telling me when a turn finishes, only when I am needed
CORAX_REDACT=1        # send the host and the reason, but no folder or branch
CORAX_TURN_WINDOW=90  # deduplication window for turn events, seconds
CORAX_PERM_WINDOW=20  # and for permission prompts, which get their own
```

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

Your token lives in `~/.config/corax/config` at mode 600 and is never passed on a
command line, so it does not appear in `ps` to other users on a shared box.

## What it is not

It does not read your code, summarise anything, or call a model. It is a hook
that notices four kinds of event and sends you two lines of text.

It only knows about Claude Code. The event parsing is specific to Claude Code's
hook payloads, and that specificity is the whole point. Another agent would be a
new file, not a rewrite.

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
