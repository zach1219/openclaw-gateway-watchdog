# OpenClaw Gateway Watchdog

Windows watchdog that monitors [OpenClaw](https://github.com/openclaw/openclaw) Gateway health and auto-restarts on failure.

## Features

- **Dual detection**: TCP port probe + process alive check
- **Consecutive failure threshold**: Avoids false positives from transient glitches
- **Kill + restart**: Terminates residual processes, then launches gateway
- **Post-restart verification**: Confirms gateway is alive before notifying
- **Mutex lock**: Prevents multiple watchdog instances
- **Notifications**: Feishu bot and generic webhook support

## Quick Start

1. Copy scripts/watchdog.ps1 and scripts/deploy.ps1 to a local directory.
2. Edit watchdog.ps1 config section — set ` $GatewayCmdPath `, ` $GatewayPort `, and optionally configure notifications.
3. Deploy as Scheduled Task (requires admin PowerShell):

`powershell
.\deploy.ps1
`

## Installation as OpenClaw Skill

Clone or download this repo into your OpenClaw skills directory:

`powershell
git clone https://github.com/zach1219/openclaw-gateway-watchdog.git ~/.openclaw/workspace/skills/gateway-watchdog
`

Then follow the Quick Start above.

## Configuration

All configuration is at the top of watchdog.ps1:

| Variable | Default | Description |
|----------|---------|-------------|
| ` $GatewayPort ` | 18789 | Gateway listen port |
| ` $GatewayCmdPath ` | auto-detected | Path to gateway startup script |
| ` $RetryIntervalSec ` | 5 | Seconds between checks |
| ` $ConsecutiveFailMax ` | 2 | Failures before restart |
| ` $CooldownSec ` | 30 | Cooldown after successful restart |

## Notifications

Supports Feishu bot and generic webhook. See [references/notifications.md](references/notifications.md) for setup.

## Manual Run

`powershell
powershell -ExecutionPolicy Bypass -File "watchdog.ps1"
`

## Uninstall

`powershell
schtasks /Delete /TN "OpenClawGatewayWatchdog" /F
`

## License

MIT