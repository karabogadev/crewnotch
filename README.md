<div align="center">
  <h1>CrewNotch</h1>
  <p><strong>Every AI coding agent, live in your MacBook notch.</strong></p>
  <p>Claude Code · Codex · Cursor · Gemini CLI · Antigravity · DeepSeek Harness · OpenCode · Copilot CLI · Grok · Kiro</p>
</div>

> 🚧 **In active development.** The first release is on its way. Watch the repo to get notified.

CrewNotch shows what each of your AI coding agents is doing (working, finished or waiting for you) in a Dynamic Island-style panel that grows out of the MacBook notch. You can approve tool calls without switching windows, and you'll hear a sound when a long task is done.

## Planned for v1

- **Every agent in one place.** Live status for Claude Code, Codex, Cursor, Gemini CLI, Antigravity, DeepSeek Harness, OpenCode, Copilot CLI, Grok and Kiro.
- **Know when an agent needs you.** Finished turns, questions and approval requests surface in the notch, with sounds.
- **Approve from the notch.** Allow or deny tool calls for Claude Code, Codex and Copilot CLI.
- **Keep Awake.** Agents keep working when the display sleeps or the screen locks, with battery and time limits.
- **Plan usage.** See how much of your Claude and Codex limits you've used.
- **Private by design.** No accounts, no analytics. Everything stays on your Mac.

## Build from source

Requires macOS 15.6+ and Xcode 26+.

```bash
xcodebuild -scheme CrewNotch -configuration Release build
```

## Credits

CrewNotch started as a fork of [Vibe Notch](https://github.com/farouqaldori/vibe-notch) (formerly Claude Island) by Farouq Aldori and builds on its notch UI and Claude Code integration. Thank you!

## License

Apache License 2.0. See [LICENSE.md](LICENSE.md). Portions © Farouq Aldori.
