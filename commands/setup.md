---
description: Set up corax so this machine can message you when a session needs you
allowed-tools: Bash(sh "${CLAUDE_PLUGIN_ROOT}/corax" config:*), Bash(sh "${CLAUDE_PLUGIN_ROOT}/corax" doctor), Bash(sh "${CLAUDE_PLUGIN_ROOT}/corax" test), Bash(sh "${CLAUDE_PLUGIN_ROOT}/corax" telegram-chat:*)
---

## Context

- Current corax state: !`sh "${CLAUDE_PLUGIN_ROOT}/corax" doctor 2>&1 || true`

## Your task

Walk the user through configuring corax, then prove it works. The plugin has
already registered the hooks, so only credentials are missing.

Use `sh "${CLAUDE_PLUGIN_ROOT}/corax" config set KEY VALUE` to write settings.
Never edit the config file directly. Never print the user's token back to them.

**Step 1.** If the doctor output above already shows a working transport, say so
and skip to step 3.

**Step 2.** Ask which transport they want, and set it up:

- **ntfy** is the fastest and needs no account. Suggest it first for anyone who
  has not already got a Telegram bot. Ask them to pick a topic name nobody else
  would guess, or offer one. Then:
  `config set CORAX_TRANSPORT ntfy` and `config set CORAX_NTFY_TOPIC <topic>`.
  Tell them to install the ntfy app and subscribe to that topic.

- **telegram** needs a bot. Tell them to message @BotFather, send `/newbot`, and
  paste the token here. Then `config set CORAX_TRANSPORT telegram` and
  `config set CORAX_TELEGRAM_TOKEN <token>`. Now ask them to send any message to
  their new bot, and run `telegram-chat <token>` to read the chat id back. If it
  exits non-zero, the message has not arrived yet: wait a moment and try again, up
  to about five times. When you get an id, `config set CORAX_TELEGRAM_CHAT <id>`.

- **slack** needs an incoming webhook. Tell them to create a Slack app, turn on
  Incoming Webhooks, add one to the channel they want, and paste the URL here.
  Then `config set CORAX_TRANSPORT slack` and
  `config set CORAX_SLACK_WEBHOOK_URL <url>`. Treat that URL as a password:
  never print it back to them.

- **discord** needs an incoming webhook too. Tell them to open the channel, then
  Edit Channel, Integrations, Webhooks, New Webhook, Copy Webhook URL. Then
  `config set CORAX_TRANSPORT discord` and
  `config set CORAX_DISCORD_WEBHOOK_URL <url>`. Same rule: it is a password.

- **twilio** sends real SMS and bills them per message. Say that before anything
  else, and only go on if they still want it. The account sid and auth token are
  on the Twilio console dashboard, and they need a Twilio number to send from.
  Then `config set CORAX_TRANSPORT twilio`, `config set CORAX_TWILIO_SID <sid>`,
  `config set CORAX_TWILIO_TOKEN <token>`, `config set CORAX_TWILIO_FROM <+number>`
  and `config set CORAX_TWILIO_TO <+number>`, all in E.164.

  Then `config set CORAX_STOP 0`. A turn ends on every exchange, so without this
  they get a billed text for each one. Tell them you have done it, and that
  anything actually blocking them still sends. `whatsapp:` in front of both
  numbers sends WhatsApp instead of SMS.

- **webhook**: ask for the URL, then `config set CORAX_TRANSPORT webhook` and
  `config set CORAX_WEBHOOK_URL <url>`. corax POSTs `{"text": "..."}` to it.

- **command**: ask for the command, then `config set CORAX_TRANSPORT command` and
  `config set CORAX_COMMAND <command>`. It receives the message as one argument.

**Step 3.** Run `test`. It sends one message of each kind. Ask the user to confirm
they arrived.

**Step 4.** Run `doctor` and report anything it flags. In particular, if it warns
that corax is installed both as a plugin and in settings.json, tell them to run
`corax hooks uninstall` to drop the settings.json copy and keep the plugin.

**Step 5.** Tell them two things, briefly:

- Restart any Claude Code session that is already running, so it picks up the hooks.
- Drop a `.no-corax` file in any repo whose folder and branch names should never
  leave the machine.

Keep the whole exchange short. Ask one question at a time and wait for the answer.
