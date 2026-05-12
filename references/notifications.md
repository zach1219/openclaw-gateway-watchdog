# Notification Setup

The watchdog supports two notification channels, triggered when the gateway
is auto-recovered after failure.

## Feishu Bot

Send recovery notifications to a Feishu user via bot message.

### Prerequisites

1. A Feishu app with `im:message:send_as_bot` permission
2. The target user's `open_id`

### Configuration

In `watchdog.ps1`, set:

```powershell
$NotificationMethod = "feishu"
$FeishuAppId        = "cli_xxxxxxxxxxxxxxxx"
$FeishuAppSecret    = "your_app_secret"
$FeishuUserOpenId   = "ou_xxxxxxxxxxxxxxxx"
```

### Getting an open_id

Use the Feishu API explorer or call the
[contacts API](https://open.feishu.cn/document/server-docs/contact-v3/user/get)
with the user's email or user_id.

## Generic Webhook

POST a JSON payload to any URL on recovery.

### Configuration

```powershell
$NotificationMethod = "webhook"
$WebhookUrl         = "https://your-server.com/webhook"
```

### Payload format

```json
{
  "title": "OpenClaw Gateway Recovered",
  "content": "**Auto-restart successful**\n\n- Time: 2026-05-12 16:00:00\n- Port: 18789\n- Status: Healthy",
  "timestamp": "2026-05-12T16:00:00+08:00",
  "source": "openclaw-gateway-watchdog"
}
```

### Example: n8n / Make / Zapier

Point `$WebhookUrl` to your automation webhook endpoint. The payload
includes all recovery details for further processing.

## Disabling Notifications

```powershell
$NotificationMethod = "none"
```
