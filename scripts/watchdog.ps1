#Requires -Version 5.1
<#
.SYNOPSIS
    OpenClaw Gateway Watchdog
.DESCRIPTION
    Dual detection (TCP port probe + process alive check), auto-restart on failure.
    Designed to run as a Windows Scheduled Task (single execution per invocation).
    Supports Feishu bot and generic webhook notifications.
.LINK
    https://github.com/openclaw/gateway-watchdog
#>

# ============================================================
# Configuration — Edit these values
# ============================================================

# Gateway settings
$GatewayPort        = 18789
$GatewayCmdPath     = ""  # Leave empty to auto-detect from OPENCLAW_HOME env

# Watchdog behavior
$ProbeTimeoutMs     = 3000
$RetryIntervalSec   = 5
$ConsecutiveFailMax = 2
$CooldownSec        = 30

# Notification: "feishu", "webhook", or "none"
$NotificationMethod = "none"

# Feishu notification (only used when $NotificationMethod = "feishu")
$FeishuAppId      = ""
$FeishuAppSecret  = ""
$FeishuUserOpenId = ""  # Target user's open_id

# Webhook notification (only used when $NotificationMethod = "webhook")
$WebhookUrl = ""  # POST JSON to this URL on recovery

# Logging
$MaxLogSizeMB = 10

# ============================================================
# Auto-detect gateway path if not set
# ============================================================
if ([string]::IsNullOrEmpty($GatewayCmdPath)) {
    $home = $env:OPENCLAW_HOME
    if ([string]::IsNullOrEmpty($home)) { $home = Join-Path $env:USERPROFILE ".openclaw" }
    $candidates = @(
        (Join-Path $home "gateway.cmd"),
        (Join-Path $home "gateway.bat"),
        (Join-Path $home "gateway.ps1")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { $GatewayCmdPath = $c; break }
    }
    if ([string]::IsNullOrEmpty($GatewayCmdPath)) {
        Write-Error "Cannot find gateway script. Set `$GatewayCmdPath manually or set OPENCLAW_HOME env."
        exit 1
    }
}

# ============================================================
# Logging
# ============================================================
$LogFile = Join-Path $PSScriptRoot "watchdog.log"

function Write-Log {
    param([string]$Level, [string]$Message)
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$ts] [$Level] $Message"
    if (Test-Path $LogFile) {
        $sizeMB = (Get-Item $LogFile).Length / 1MB
        if ($sizeMB -ge $MaxLogSizeMB) {
            Move-Item $LogFile "$LogFile.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak" -Force
        }
    }
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
    if ($Level -eq "ERROR") { Write-Error $line } else { Write-Host $line }
}

# ============================================================
# Notifications
# ============================================================
function Send-RecoveryNotification {
    param([string]$Title, [string]$Content)
    switch ($NotificationMethod) {
        "feishu"  { Send-FeishuMessage -Title $Title -Content $Content }
        "webhook" { Send-WebhookMessage -Title $Title -Content $Content }
        "none"    { }
    }
}

function Send-FeishuMessage {
    param([string]$Title, [string]$Content)
    if ([string]::IsNullOrEmpty($FeishuAppId) -or [string]::IsNullOrEmpty($FeishuAppSecret)) {
        Write-Log "WARN" "Feishu credentials not configured, skipping notification"
        return
    }
    try {
        $tokenResp = Invoke-RestMethod `
            -Uri "https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal" `
            -Method Post -ContentType "application/json; charset=utf-8" `
            -Body (@{ app_id = $FeishuAppId; app_secret = $FeishuAppSecret } | ConvertTo-Json)
        if ($tokenResp.code -ne 0) { Write-Log "ERROR" "Feishu token failed: $($tokenResp.msg)"; return }
        $token = $tokenResp.tenant_access_token

        $msgBody = @{
            receive_id = $FeishuUserOpenId
            msg_type   = "interactive"
            content    = (@{
                config   = @{ wide_screen_mode = $true }
                header   = @{ title = @{ content = $Title; tag = "plain_text" }; template = "green" }
                elements = @(
                    @{ tag = "markdown"; content = $Content }
                    @{ tag = "note"; elements = @(@{ tag = "plain_text"; content = "OpenClaw Gateway Watchdog" }) }
                )
            }) | ConvertTo-Json -Depth 10
        } | ConvertTo-Json -Depth 3

        $msgResp = Invoke-RestMethod `
            -Uri "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=open_id" `
            -Method Post -ContentType "application/json; charset=utf-8" `
            -Headers @{ Authorization = "Bearer $token" } -Body $msgBody
        if ($msgResp.code -eq 0) { Write-Log "INFO" "Feishu notification sent" }
        else { Write-Log "ERROR" "Feishu send failed: $($msgResp.msg)" }
    } catch {
        Write-Log "ERROR" "Feishu notification error: $($_.Exception.Message)"
    }
}

function Send-WebhookMessage {
    param([string]$Title, [string]$Content)
    if ([string]::IsNullOrEmpty($WebhookUrl)) {
        Write-Log "WARN" "Webhook URL not configured, skipping notification"
        return
    }
    try {
        $body = @{
            title     = $Title
            content   = $Content
            timestamp = (Get-Date -Format "o")
            source    = "openclaw-gateway-watchdog"
        } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri $WebhookUrl -Method Post `
            -ContentType "application/json; charset=utf-8" -Body $body
        Write-Log "INFO" "Webhook notification sent"
    } catch {
        Write-Log "ERROR" "Webhook notification error: $($_.Exception.Message)"
    }
}

# ============================================================
# Port probe
# ============================================================
function Test-GatewayPort {
    param([int]$Port, [int]$TimeoutMs)
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $ar  = $tcp.BeginConnect("127.0.0.1", $Port, $null, $null)
        $ok  = $ar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
        if ($ok -and $tcp.Connected) { $tcp.EndConnect($ar); $tcp.Close(); return $true }
        $tcp.Close(); return $false
    } catch { return $false }
}

# ============================================================
# Process alive check
# ============================================================
function Get-GatewayProcess {
    Get-Process node -ErrorAction SilentlyContinue | Where-Object {
        try {
            $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction Stop).CommandLine
            $cmd -match "openclaw" -or $cmd -match "gateway"
        } catch { $false }
    }
}

function Test-GatewayAlive {
    $portOK = Test-GatewayPort -Port $GatewayPort -TimeoutMs $ProbeTimeoutMs
    $procs  = Get-GatewayProcess
    $procOK = $null -ne $procs -and $procs.Count -gt 0
    [PSCustomObject]@{
        PortOK       = $portOK
        ProcessOK    = $procOK
        ProcessCount = if ($procs) { $procs.Count } else { 0 }
        BothOK       = $portOK -and $procOK
    }
}

# ============================================================
# Cleanup
# ============================================================
function Stop-GatewayProcesses {
    $procs = Get-GatewayProcess
    if ($procs) {
        foreach ($p in $procs) {
            Write-Log "WARN" "Killing residual process PID=$($p.Id)"
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
    }
}

# ============================================================
# Restart gateway
# ============================================================
function Start-Gateway {
    if (-not (Test-Path $GatewayCmdPath)) {
        Write-Log "ERROR" "Gateway script not found: $GatewayCmdPath"
        return $false
    }
    Write-Log "INFO" "Starting gateway: $GatewayCmdPath"
    try {
        $ext = [System.IO.Path]::GetExtension($GatewayCmdPath).ToLower()
        if ($ext -eq ".ps1") {
            Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$GatewayCmdPath`"" `
                -WindowStyle Hidden
        } else {
            Start-Process -FilePath "cmd.exe" `
                -ArgumentList "/c `"$GatewayCmdPath`"" `
                -WindowStyle Hidden
        }
        Start-Sleep -Seconds 5
        $check = Test-GatewayAlive
        if ($check.BothOK) {
            Write-Log "INFO" "Gateway started (port=$($check.PortOK) procs=$($check.ProcessCount))"
            $now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            Send-RecoveryNotification -Title "OpenClaw Gateway Recovered" `
                -Content "**Auto-restart successful**`n`n- Time: $now`n- Port: $GatewayPort`n- Status: Healthy"
            return $true
        } else {
            Write-Log "ERROR" "Gateway start verification failed (port=$($check.PortOK) proc=$($check.ProcessOK))"
            return $false
        }
    } catch {
        Write-Log "ERROR" "Start gateway exception: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================
# Main
# ============================================================
$mutexCreated = $false
$mutex = [System.Threading.Mutex]::new($true, "Global\OpenClawGatewayWatchdog", [ref]$mutexCreated)
if (-not $mutexCreated) {
    Write-Log "WARN" "Another watchdog instance is running, exiting."
    exit 0
}

try {
    Write-Log "INFO" "=== Watchdog started (port=$GatewayPort, threshold=$ConsecutiveFailMax) ==="
    $consecutiveFails = 0
    while ($true) {
        $alive = Test-GatewayAlive
        if ($alive.BothOK) {
            if ($consecutiveFails -gt 0) {
                Write-Log "INFO" "Recovered, resetting counter (was=$consecutiveFails)"
            }
            $consecutiveFails = 0
        } else {
            $consecutiveFails++
            Write-Log "WARN" "Check failed ($consecutiveFails/$ConsecutiveFailMax) — port=$($alive.PortOK) proc=$($alive.ProcessOK) procs=$($alive.ProcessCount)"
            if ($consecutiveFails -ge $ConsecutiveFailMax) {
                Write-Log "ERROR" "Threshold reached, restarting gateway"
                Stop-GatewayProcesses
                if (Start-Gateway) {
                    Write-Log "INFO" "Restart OK, cooling down ${CooldownSec}s"
                    $consecutiveFails = 0
                    Start-Sleep -Seconds $CooldownSec
                } else {
                    Write-Log "ERROR" "Restart failed, waiting for next check"
                }
            }
        }
        Start-Sleep -Seconds $RetryIntervalSec
    }
} finally {
    $mutex.ReleaseMutex()
    $mutex.Dispose()
    Write-Log "INFO" "=== Watchdog exited ==="
}
