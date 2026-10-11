# cachyAgent

Agentic layer for KDE / CachyOS: a fast launcher menu, a dependency-checking installer, crash detection with one-shot diagnosis, local usage tracking with a Plasma widget, and a global shortcut.

## Features

- **Catalog-driven menu** — agents come from a single `agents.conf` file; every script and the plasmoid read it. Adding an agent is one config line.
- **Dependency-checking installer** — `install.sh` audits dependencies, installs the scripts, and writes `agents.conf` (only if absent, so your edits survive reinstalls).
- **Crash notification + diagnose** — a `crash-watch` helper detects abnormal agent exits, sends a desktop notification, and offers a one-shot `diagnose` run.
- **Usage tracking + plasmoid** — local collectors for `codex`, `copilot` and `opencode`; a Plasma 6 plasmoid shows recent usage at a glance.
- **Global shortcut** — one keybinding opens the agent menu from anywhere in Plasma (registered manually in KDE, see below).

## Requirements

- CachyOS / Arch Linux
- KDE Plasma 6
- `fuzzel`
- `alacritty`
- `fish`
- `mise`
- `python-gobject` (`python3 -c 'import gi'`)
- `journalctl` (systemd)
- `kwriteconfig6` (kconfig)

## Installation

```bash
./install.sh
```

The installer checks the requirements above, installs the menu scripts, writes `agents.conf` if it does not already exist, installs the plasmoid, and enables the crash watcher plus the usage-refresh service and its timer. **It does not register the global shortcut** — do that once by hand: System Settings › Keyboard › Shortcuts › cachyAgent › Launch.

## Usage

Open the agent menu (pick one):

- Press the **global shortcut** (registered by hand, see Installation), or
- Click the **Plasma panel icon** / run the launcher entry, or
- Run `cachy-agent-menu` in a terminal.

In `fish`, the helper defines two aliases that start an agent **directly** (they do not open the menu):

- `a` — the default agent (`cachy-agent --inline`)
- `ga` — `agy` specifically (`cachy-agent --inline agy`)

Examples:

```bash
# run the default agent directly
a

# agy directly
ga

# open the agent menu
cachy-agent-menu
```

Crash flow:

1. An agent process exits abnormally.
2. `crash-watch` posts a desktop notification.
3. Accept the action to run a one-shot `diagnose` capturing logs and environment.

## Screenshot

![agent menu](docs/screenshot-menu.png)

## Uninstallation

```bash
./uninstall.sh
```

Removes the menu entries, plasmoid, and crash watcher installed by `install.sh`.

## Configuration

All agents live in one file: `~/.config/cachy-agent/agents.conf`.

```ini
# Format: id=görünen_ad|install|flags|prompt_flag|login
claude=Claude Code|npm i -g @anthropic-ai/claude-code|--permission-mode auto|-p|claude login
codex=Codex|npm i -g @openai/codex|--approve-for-me|-|codex login
```

- `install` is the command `cachy-agent-install <id>` runs after you confirm; `-` means "no automatic install" (the agent ships outside the package manager).
- `flags` are passed on every launch.
- `prompt_flag` is how the agent takes a prompt (`--prompt`, `-p`); `-` means the prompt is passed positionally.
- `login` is the hint shown when launch fails; `-` means no login needed.

Edit freely — `install.sh` only writes the file when it is absent, so reinstalls keep your changes. `WORKDIR=` sets the directory `a`/`ga` open in (default `~/Projeler`). Full reference: `docs/agents.md`.

## Testing

```bash
./tests/smoke.sh                  # repo health: syntax, placeholders, unit files
./tests/test.sh                   # full suite; runs without installing anything
./tests/argv-differential.sh --check   # agent launch argv against a measured baseline
```

The suite runs from a bare checkout with no network, no credentials and no real agent CLIs.

## Known Limitations

- Agent quota is not checked programmatically for agents without a collector — monitor usage manually.
- Usage tracking has a collector for only 3 of the 8 catalog agents (`opencode`, `codex`, `copilot`); the other five (`agy`, `claude`, `crush`, `cursor-agent`, `grok`) are not collected — see `docs/usage-schema.md`.
- `claude login` is required before Claude-based agents will work; the installer checks the CLI exists but cannot authenticate for you.
