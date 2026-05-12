---
name: gateway-watchdog
description: >
  Monitor and auto-restart OpenClaw Gateway on Windows. Use when setting up
  gateway health monitoring, auto-recovery, or watchdog for OpenClaw. Triggers
  on keywords: watchdog, gateway monitor, auto-restart, health check, 鐪嬮棬鐙?
  缃戝叧鐩戞帶, 鑷姩閲嶅惎.
---

# Gateway Watchdog

Windows watchdog that monitors OpenClaw Gateway health via dual detection
(TCP port probe + process alive check) and auto-restarts on failure.

**Source**: [github.com/zach1219/openclaw-gateway-watchdog](https://github.com/zach1219/openclaw-gateway-watchdog)

## Quick Start

1. Copy `scripts/watchdog.ps1` and `scripts/deploy.ps1` to a local directory.
2. Edit `watchdog.ps1` config section 鈥?set `$GatewayCmdPath`, `$GatewayPort`,
   and optionally configure notifications (Feishu/webhook).
3. Deploy as Scheduled Task (requires admin PowerShell):

```powershell
.\deploy.ps1
```

## Configuration

All configuration is at the top of `watchdog.ps1`:

| Variable | Default | Description |
|----------|---------|-------------|
| `$GatewayPort` | 18789 | Gateway listen port |
| `$GatewayCmdPath` | auto-detected | Path to gateway startup script |
| `$RetryIntervalSec` | 5 | Seconds between checks |
| `$ConsecutiveFailMax` | 2 | Failures before restart |
| `$CooldownSec` | 30 | Cooldown after successful restart |

### Notifications

Supports Feishu bot and generic webhook. See
[references/notifications.md](references/notifications.md) for setup.

Set `$NotificationMethod` to `"feishu"`, `"webhook"`, or `"none"`.

## How It Works

1. **Dual detection**: TCP probe on gateway port + WMI process check
2. **Consecutive failure threshold**: Avoids false positives from transient glitches
3. **Kill + restart**: Terminates娈嬬暀 processes, then launches gateway
4. **Post-restart verification**: Confirms gateway is alive before notifying
5. **Mutex lock**: Prevents multiple watchdog instances

## Files

- `scripts/watchdog.ps1` 鈥?Main watchdog (single execution, designed for Scheduled Task)
- `scripts/deploy.ps1` 鈥?Creates Windows Scheduled Task
- `references/notifications.md` 鈥?Notification channel setup guide

## Manual Run

```powershell
powershell -ExecutionPolicy Bypass -File "watchdog.ps1"
```

Press `Ctrl+C` to stop.

## Uninstall

```powershell
schtasks /Delete /TN "OpenClawGatewayWatchdog" /F
```

