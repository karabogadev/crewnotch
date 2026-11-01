<div align="center">
  <img src="docs/hero.png" alt="CrewNotch: every AI coding agent, live in your MacBook notch" width="100%">

  <p>
    <a href="https://github.com/karabogadev/crewnotch/releases/latest"><img alt="Release" src="https://img.shields.io/github/v/release/karabogadev/crewnotch?style=flat-square&color=white&labelColor=000000&label=release"></a>
    <img alt="macOS 15.6+" src="https://img.shields.io/badge/macOS-15.6%2B-white?style=flat-square&labelColor=000000">
    <img alt="Swift" src="https://img.shields.io/badge/Swift-SwiftUI-white?style=flat-square&labelColor=000000">
    <a href="LICENSE.md"><img alt="License" src="https://img.shields.io/badge/license-Apache%202.0-white?style=flat-square&labelColor=000000"></a>
  </p>

  <p><strong>Know which agent is working, which one is done, and which one needs you, without leaving what you're doing.</strong></p>
</div>

---

You run Claude Code in one terminal, Codex in another, Cursor and Antigravity in their own windows, and a DeepSeek Harness session in the background. One of them finished ten minutes ago. Another has been waiting on an approval the whole time.

**CrewNotch puts all of them in the notch.** The notch quietly shows the busiest agent while your crew works. It tells you the moment a turn finishes or an agent asks for permission, and one click takes you back to the right terminal or window.

## Highlights

- **Every agent in one place.** Claude Code, Codex, Cursor, Gemini CLI, Antigravity, DeepSeek Harness, OpenCode, Copilot CLI, Grok and Kiro. Each one shows up with its own logo.
- **Working, done, needs you, at a glance.** The closed notch shows the agent that matters most right now, plus a status mark: working, finished or waiting on you.
- **Approve from the notch.** Allow or deny Claude Code and Codex tool calls without switching windows.
- **A finished banner.** When an agent finishes and you're looking elsewhere, the notch drops down for a moment: *Finished · storefront · Open ↗*.
- **Back in one click.** Double-click a session to bring its terminal (or tmux pane, with yabai) or app window to the front.
- **Plan usage in the notch.** Session and weekly limits for Claude and Codex, with no separate app.
- **Token history.** Tokens per day across agents, the estimated API value of your Claude usage, and your busiest day. Share it as an image.
- **Keep Awake.** Agents keep running when the display sleeps or the screen locks. It works on power adapter only, stops below a battery threshold and turns itself off after a time limit.
- **Make it yours.** Six working indicators, notch animations, materials and colors, sounds per event, text size and much more.
- **Private by design.** No account and no analytics. Everything stays on your Mac.

## Supported agents

| Agent | How CrewNotch connects | Live status | Approve from notch | Plan usage |
|---|---|:-:|:-:|:-:|
| **Claude Code** | Hooks in `~/.claude/settings.json` | ✓ | ✓ | ✓ |
| **Codex** | Hooks in `~/.codex/hooks.json` | ✓ | ✓ | ✓ |
| **Cursor** | Hooks in `~/.cursor/hooks.json` | ✓ | | |
| **Gemini CLI** | Hooks in `~/.gemini/settings.json` | ✓ | | |
| **Antigravity** (app and IDE) | A named hook in `~/.gemini/config/hooks.json` | ✓ | | |
| **DeepSeek Harness** | Reads its session logs, nothing installed | ✓ | | |
| **OpenCode** | A small plugin in `~/.config/opencode/plugin/` | ✓ | | |
| **Copilot CLI** | Its own file in `~/.copilot/hooks/` | ✓ | | |
| **Grok** | Its own file in `~/.grok/hooks/` | ✓ | | |
| **Kiro** | Its own file in `~/.kiro/hooks/` (v3 engine) | ✓ | | |

Agents without a notch approval still show when they need you, and an **Open** button takes you straight to them.

## How it works

```mermaid
flowchart LR
    subgraph Agents
        A[Claude Code · Codex · Cursor<br/>Gemini · Antigravity · Copilot<br/>Grok · Kiro]
        O[OpenCode plugin]
        D[DeepSeek Harness<br/>session logs]
    end
    A -- hook --> H[crewnotch-hook.py]
    H -- JSON --> S[(~/.crewnotch/crewnotch.sock)]
    O -- JSON --> S
    D -- zstd log tail --> N
    S --> N[CrewNotch]
    N --> U[Notch · sounds · banner]
    N -. allow / deny .-> H
```

- **One small hook script.** Every hook-based agent runs `~/.crewnotch/bin/crewnotch-hook.py --agent <name>`. The script turns that agent's events into the same few states (working, finished, needs you) and sends them to the app over a local socket.
- **Observe-only.** If CrewNotch isn't running, or anything goes wrong, the hook exits quietly and your agent carries on as if it weren't there. Hooks never change an agent's behavior, apart from an approval you give from the notch.
- **Careful with your config.** CrewNotch only adds or removes its own entries. Your settings and other tools' hooks stay exactly as they were.
- **Local socket only.** The socket lives in a folder only your user can access, and the hook refuses to talk to a socket owned by anyone else.

## Install

**Download:** grab the latest `.dmg` from [Releases](https://github.com/karabogadev/crewnotch/releases/latest) and drag CrewNotch to Applications.

**Build from source** (macOS 15.6+, Xcode 26 or later):

```bash
git clone https://github.com/karabogadev/crewnotch.git
cd crewnotch
xcodebuild -scheme CrewNotch -configuration Release build
```

## First launch

A short setup walks you through three steps:

1. **Welcome.** What CrewNotch does.
2. **Connect your agents.** CrewNotch lists the agents it found on your Mac. Connect them one by one or with **Connect all**. Nothing is installed without a click.
3. **Make it yours.** Sounds, approving from the notch, Keep Awake, plan usage and open at login.

You can change everything later from the ⚙︎ in the notch.

## Settings at a glance

| Pane | What's inside |
|---|---|
| **General** | Launch at login, which display shows the notch, Keep Awake and its limits |
| **Notifications** | Live notch preview, show requests, reply from the notch, finished banner, a sound per event |
| **Appearance** | Text size, panel material and color, what the closed notch shows, session list options, working indicator, animations |
| **Usage** | Line, Bars or Compact layout, used or left, provider order and per-metric visibility |
| **Agents** | Every supported agent with its status: connect, disconnect, setup notes |

## Privacy

- No account, no telemetry, no analytics.
- Agent activity comes from hooks and log files on your Mac and never leaves it.
- **Codex usage** is read from Codex's local session files.
- **Claude usage** is opt-in. CrewNotch reads Claude Code's existing sign-in from the keychain (macOS asks once) and calls Anthropic's usage endpoint at most every five minutes. The token is never refreshed or written.
- **Token history** is computed from local logs and cached in `~/.crewnotch/token-history.json`.

## Troubleshooting

<details>
<summary><strong>Codex doesn't show up</strong></summary>

Codex asks you to review new hooks the next time it starts. Choose **Trust all and continue**.
</details>

<details>
<summary><strong>Antigravity or OpenCode doesn't show up</strong></summary>

Both load hooks and plugins at startup. Quit and reopen the app after connecting it.
</details>

<details>
<summary><strong>Kiro doesn't show up</strong></summary>

Kiro only runs global hooks with its v3 engine: start it with `kiro-cli chat --v3`.
</details>

<details>
<summary><strong>Claude usage says "Open Claude Code to renew sign-in"</strong></summary>

Claude Code refreshes its own sign-in while it runs. Open it once, and usage comes back within five minutes.
</details>

<details>
<summary><strong>Another notch app is also running</strong></summary>

Two notch apps draw in the same place and both play sounds. Quit the other one while using CrewNotch.
</details>

## Uninstall

Open **Settings → Agents** and press **Disconnect** for each agent; this removes CrewNotch's hooks and plugin files. Then quit CrewNotch, move it to the Trash and delete `~/.crewnotch`.

## Roadmap

- Plan usage for Antigravity, Cursor and Copilot
- Light panel themes
- An agent detail page with diagnostics
- A Homebrew cask

Ideas and bug reports are welcome in [Issues](https://github.com/karabogadev/crewnotch/issues).

## Credits

CrewNotch started as a fork of [Vibe Notch](https://github.com/farouqaldori/vibe-notch) (formerly Claude Island) by Farouq Aldori and builds on its notch UI and Claude Code integration. Thank you!

Agent logos come from [LobeHub Icons](https://github.com/lobehub/lobe-icons) (MIT). Each logo is a trademark of its owner and is shown only to identify the integration. Usage endpoints follow the documentation in [OpenUsage](https://github.com/robinebers/openusage) (MIT).

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md).
