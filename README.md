# Ubuntu Keyboard Layer

A simple, configurable keyboard shortcut manager for **Ubuntu GNOME**.

Define your keyboard shortcuts in one configuration file, apply them with a single command, and restore your original GNOME shortcuts whenever you need to.

You do not need to open GNOME Settings and configure shortcuts one by one.

## Features

- **One configuration file:** Manage your shortcuts in `keybindings.conf`.
- **Simple syntax:** Use an easy `KEYS = ACTION` format.
- **Additive mode:** Keep existing GNOME shortcuts and add your own.
- **Takeover mode:** Replace existing shortcuts for actions managed by this tool.
- **Automatic conflict handling:** Detect and free keys that are already assigned to other GNOME actions.
- **Backup and restore:** Save the original GNOME settings before making changes.
- **Preview mode:** Review planned changes without applying them.
- **Status check:** See which configured shortcuts are active.
- **Custom commands:** Launch any executable command with a keyboard shortcut.
- **Easy removal:** Restore your previous keyboard settings with one command.

## Default Shortcuts

The project includes the following example configuration:

| Shortcut | Action |
|---|---|
| `Super + Enter` | Open Terminal |
| `Super + E` | Open Files |
| `Super + B` | Open the default browser |
| `Super + Space` | Open GNOME Overview |
| `Super + W` | Close the focused window |
| `Super + F` | Toggle window maximisation |
| `Super + Shift + F` | Toggle fullscreen |
| `Super + N` | Minimise the focused window |
| `Super + Left` | Tile the window to the left |
| `Super + Right` | Tile the window to the right |
| `Super + Shift + Arrow` | Move the window between monitors |
| `Super + 1–9` | Switch workspace |
| `Super + 0` | Switch to the last workspace |
| `Super + Shift + 1–9` | Move the window to a workspace |
| `Super + Shift + 0` | Move the window to the last workspace |
| `Super + L` | Lock the screen |
| `Super + Shift + S` | Open the screenshot interface |
| `Super + V` | Toggle the notification tray |

These are only defaults. Edit `keybindings.conf` to add, change, or remove shortcuts.

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/YOUR_USERNAME/ubuntu-keyboard-layer.git
```

> Replace `YOUR_USERNAME` with the GitHub account or organisation that hosts the repository.

### 2. Open the project directory

```bash
cd ubuntu-keyboard-layer
```

### 3. Make the script executable

```bash
chmod +x keyboard.sh
```

That is it. You can now run the script.

## Usage

### Open the interactive menu

```bash
./keyboard.sh
```

You can also run each command directly.

| Command | What it does |
|---|---|
| `./keyboard.sh apply` | Apply the shortcuts in `keybindings.conf`. |
| `./keyboard.sh preview` | Show the changes that would be made, without applying them. |
| `./keyboard.sh status` | Check which configured shortcuts are currently active. |
| `./keyboard.sh remove` | Remove the keyboard layer and restore the saved GNOME shortcuts. |

**Recommended:** Run `preview` before applying a new or significantly changed configuration.

## Configuration

All shortcut settings are managed through one file:

```text
keybindings.conf
```

The `keyboard.sh` script reads this file and applies the configuration.

### Basic format

Each shortcut uses this format:

```ini
KEYS = ACTION
```

For example:

```ini
SUPER+ENTER = terminal
SUPER+E     = files
SUPER+B     = browser
SUPER+L     = lock
```

### 1. Supported modifiers

Combine modifiers with `+`.

| Modifier | Key |
|---|---|
| `SUPER` | Super / Windows key |
| `CTRL` | Control key |
| `ALT` | Alt key |
| `SHIFT` | Shift key |

Examples:

```ini
SUPER+ENTER = terminal
SUPER+SHIFT+S = screenshot
CTRL+ALT+T = exec:gnome-terminal
```

### 2. Supported keys

The following keys are supported:

- **Letters:** `A`–`Z`
- **Numbers:** `0`–`9`
- **Function keys:** `F1`–`F12`
- **Special keys:** `ENTER`, `SPACE`, `TAB`, `ESC`, `UP`, `DOWN`, `LEFT`, `RIGHT`, `PAGEUP`, `PAGEDOWN`

Examples:

```ini
SUPER+E = files
SUPER+SHIFT+F = toggle-fullscreen
CTRL+ALT+T = terminal
```

### 3. Supported actions

#### Application launchers

| Action | What it does |
|---|---|
| `terminal` | Open the default terminal. |
| `files` | Open Files (Nautilus). |
| `browser` | Open the default browser. |
| `overview` | Open GNOME Overview. |
| `apps` | Open the application grid. |
| `exec:<command>` | Run a custom command. |

Example:

```ini
SUPER+ENTER = terminal
SUPER+E = files
SUPER+C = exec:gnome-calculator
SUPER+T = exec:gnome-system-monitor
```

#### Window management

| Action | What it does |
|---|---|
| `close` | Close the focused window. |
| `minimize` | Minimise the focused window. |
| `maximize` | Maximise the focused window. |
| `toggle-maximized` | Toggle the window's maximised state. |
| `toggle-fullscreen` | Toggle fullscreen mode. |
| `tile:left` | Tile the window to the left. |
| `tile:right` | Tile the window to the right. |

Example:

```ini
SUPER+W = close
SUPER+F = toggle-maximized
SUPER+SHIFT+F = toggle-fullscreen
SUPER+N = minimize
SUPER+LEFT = tile:left
SUPER+RIGHT = tile:right
```

#### Monitor management

Move the focused window between connected monitors.

| Action | What it does |
|---|---|
| `move-to-monitor:left` | Move the window to the left monitor. |
| `move-to-monitor:right` | Move the window to the right monitor. |
| `move-to-monitor:up` | Move the window to the upper monitor. |
| `move-to-monitor:down` | Move the window to the lower monitor. |

Example:

```ini
SUPER+SHIFT+LEFT = move-to-monitor:left
SUPER+SHIFT+RIGHT = move-to-monitor:right
SUPER+SHIFT+UP = move-to-monitor:up
SUPER+SHIFT+DOWN = move-to-monitor:down
```

#### Workspace management

Switch to a workspace:

```ini
SUPER+1 = workspace:1
SUPER+2 = workspace:2
SUPER+3 = workspace:3
SUPER+4 = workspace:4
SUPER+0 = workspace:last
```

Move the focused window to another workspace:

```ini
SUPER+SHIFT+1 = move-to-workspace:1
SUPER+SHIFT+2 = move-to-workspace:2
SUPER+SHIFT+3 = move-to-workspace:3
SUPER+SHIFT+0 = move-to-workspace:last
```

> **Note:** GNOME uses dynamic workspaces. A shortcut can switch to a workspace only when that workspace exists. GNOME creates additional workspaces as you navigate through them.

#### System actions

| Action | What it does |
|---|---|
| `lock` | Lock the screen. |
| `screenshot` | Open the screenshot interface. |
| `notifications` | Toggle the notification tray. |

Example:

```ini
SUPER+L = lock
SUPER+SHIFT+S = screenshot
SUPER+V = notifications
```

#### Advanced: Custom GNOME settings

You can also set a GNOME keyboard shortcut directly with a `gsettings` action:

```ini
gsettings:<schema> <key>
```

Example:

```ini
SUPER+Q = gsettings:org.gnome.desktop.wm.keybindings close
```

Use this when you need a GNOME shortcut that is not included in the built-in actions.

## Configuration modes

The keyboard layer supports two modes. Set the mode near the top of `keybindings.conf`.

### Additive mode (recommended)

```ini
@mode = additive
```

- Keeps existing shortcuts for actions managed by your configuration.
- Adds your shortcuts alongside the existing ones.
- For example, if you assign `SUPER+W` to close a window, the existing `ALT+F4` shortcut continues to work.

### Takeover mode

```ini
@mode = takeover
```

- Replaces existing shortcuts for actions managed by your configuration.
- Keeps only the shortcuts defined in your configuration for those actions.
- Useful when you want full control over the shortcut layout.

### How conflicts are handled

In both modes, the script checks whether a shortcut is already assigned to a different GNOME action. If it finds a conflict, it removes the conflicting assignment so your configured shortcut can work.

The affected settings are backed up first. Run the following command to restore them:

```bash
./keyboard.sh remove
```

## Add your own shortcuts

Use the `exec:` action to bind a shortcut to a command available on your system.

For example:

```ini
SUPER+C = exec:gnome-calculator
SUPER+T = exec:gnome-system-monitor
SUPER+P = exec:code
CTRL+ALT+T = exec:gnome-terminal
```

After editing `keybindings.conf`, apply the changes:

```bash
./keyboard.sh apply
```

To disable a shortcut, comment out its line by adding `#` at the beginning:

```ini
# SUPER+C = exec:gnome-calculator
```

### Configuration rules

- Use one action for each key combination.
- Do not define the same key combination more than once.
- Lines beginning with `#` are comments and are ignored.
- Do not use quotes in `exec:` commands.
- Use valid modifiers, keys, and actions.

## Backup and restore

This project is designed to make keyboard customisation reversible.

Before changing an existing GNOME setting, the script saves its original value.

Backups are stored outside the project directory:

```text
~/.local/state/ubuntu-keyboard-layer/backup.tsv
```

The backup system is designed to:

- Preserve the original GNOME shortcut assignments.
- Avoid intentionally removing existing custom shortcuts.
- Use the original backed-up settings when the configuration is applied again.
- Restore the saved settings when the keyboard layer is removed.

You do not need to manage the backup file yourself.

To remove the keyboard layer and restore the saved settings, run:

```bash
./keyboard.sh remove
```

> **Important:** Do not manually delete the backup file while the keyboard layer is active. Without it, the script may not be able to restore your original settings.

## Requirements

- Ubuntu with the GNOME desktop.
- An active graphical GNOME session.
- Bash.
- Python 3.
- `gsettings` (included with GNOME).

### Important setup notes

- Run the script from a terminal inside your desktop session.
- **Do not run the script with `sudo` or as root.**
- The script changes keyboard settings for your current user only. It does not change system-wide settings.

## Project structure

```text
ubuntu-keyboard-layer/
├── keyboard.sh
├── keybindings.conf
└── README.md
```

| File | Description |
|---|---|
| `keyboard.sh` | Main script for managing GNOME keyboard shortcuts. |
| `keybindings.conf` | Configuration file containing your shortcut mappings. |
| `README.md` | Project documentation. |

## Important notes

- This project is designed for Ubuntu GNOME.
- Some actions may not be available on every GNOME version.
- The script skips GNOME settings that do not exist on your system.
- `SUPER+SPACE` may conflict with keyboard layout switching.
- The `browser` action opens your system's default browser.
- Custom commands must be installed and available on your system.
- Workspace shortcuts depend on the requested workspace being available.
- Preview your changes before applying a significantly modified configuration.

## Contributing

Contributions, bug reports, and suggestions are welcome.

To contribute:

1. Fork the repository.
2. Create a new branch for your changes.
3. Make and test your changes.
4. Submit a pull request.

Suggestions for new actions, improved shortcut handling, and a better configuration format are also welcome.

## License

Choose and add a license before publishing this project publicly.

The MIT License is one option if you want others to use, modify, and distribute the project with few restrictions. Do not describe the project as MIT-licensed unless you have added the appropriate license file.

---

Built to make Ubuntu keyboard customisation simple, flexible, and reversible.
