# Claude Code Notification Lab

Automatically send Windows desktop Toast notifications when a Claude Code instance finishes thinking or needs user approval — so you never miss it while running multiple instances.

## Problem

When running multiple Claude Code instances simultaneously, some may enter long thinking phases. After switching to other windows, there's no way to know when:
- Claude has finished thinking and produced results
- Claude is waiting for user approval to proceed

## Solution

Leverage the **Claude Code Hooks** mechanism to execute a PowerShell script on key events, sending Windows Toast notifications.

### Architecture

```
Claude Code Instance
        |
        +-- Stop event ────────────┐
        +-- Notification event ────┤
        +-- StopFailure event ─────┤
                                   v
                         notify.ps1 (PowerShell)
                                   |
                                   v
                        Windows Toast Notification
```

### Hook Events

| Event | Trigger | Purpose |
|-------|---------|---------|
| `Stop` | Claude finishes a response turn | Notify: "Done thinking, check the results" |
| `Notification` | Claude is waiting for user input/approval | Notify: "Action required" |
| `StopFailure` | API error interrupts the session | Notify: "Error occurred, needs attention" |

### Hook Data Flow

Claude Code passes JSON data to hook scripts via **stdin**:

```jsonc
// Common fields (all events)
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory",
  "hook_event_name": "Stop"
}

// Additional fields for Notification events
{
  "notification_type": "permission_prompt"  // or "idle_prompt", etc.
}
```

The script reads this data to generate meaningful notification content (e.g., project name, event type).

## Project Structure

```
notificationLab0/
├── README.md                  # This file
├── .gitignore
├── scripts/
│   └── notify.ps1             # Notification script (core)
├── config/
│   └── hooks.example.json     # Example hooks configuration
└── install.ps1                # One-click installer
```

## File Descriptions

### `scripts/notify.ps1`

Core notification script. Responsibilities:
- Read JSON data from stdin (passed by Claude Code)
- Parse event type, project path, and other context
- Send a desktop notification via Windows native Toast API
- Include event type + project name in the notification to distinguish between instances

Uses the .NET `Windows.UI.Notifications` API (natively supported on Windows 10/11, no extra modules required).

### `config/hooks.example.json`

Example Claude Code hooks configuration. Copy into `~/.claude/settings.json` to activate:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:/Users/<username>/repos/notificationLab0/scripts/notify.ps1\"",
            "timeout": 10
          }
        ]
      }
    ],
    "Notification": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:/Users/<username>/repos/notificationLab0/scripts/notify.ps1\"",
            "timeout": 10
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -ExecutionPolicy Bypass -File \"C:/Users/<username>/repos/notificationLab0/scripts/notify.ps1\"",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

### `install.ps1`

Automated installer. Responsibilities:
- Detect the current username and generate the correct script path
- Read the existing `~/.claude/settings.json` (if present)
- Merge hooks configuration without overwriting existing user settings
- Write back to settings.json

## Usage

```powershell
# 1. Clone the repo
git clone <repo-url>
cd notificationLab0

# 2. Run the installer
.\install.ps1

# 3. Restart Claude Code — notifications are now active
```

## Development Plan

- [ ] Implement `scripts/notify.ps1` — Toast notification script
- [ ] Implement `config/hooks.example.json` — Configuration template
- [ ] Implement `install.ps1` — One-click installer
- [ ] End-to-end testing
