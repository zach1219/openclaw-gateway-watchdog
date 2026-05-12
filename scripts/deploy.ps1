#Requires -Version 5.1
<#
.SYNOPSIS
    Deploy OpenClaw Gateway Watchdog as a Windows Scheduled Task
.DESCRIPTION
    Creates a Scheduled Task that runs watchdog.ps1 at regular intervals.
    Run as Administrator.
#>

param(
    [string]$WatchdogScriptPath,
    [string]$TaskName = "OpenClawGatewayWatchdog",
    [int]$IntervalMinutes = 5,
    [switch]$UseSystem,
    [switch]$Force
)

# ============================================================
# Resolve script path
# ============================================================
if ([string]::IsNullOrEmpty($WatchdogScriptPath)) {
    $WatchdogScriptPath = Join-Path $PSScriptRoot "watchdog.ps1"
}
if (-not (Test-Path $WatchdogScriptPath)) {
    Write-Error "watchdog.ps1 not found: $WatchdogScriptPath"
    exit 1
}

# ============================================================
# Check existing task
# ============================================================
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    if (-not $Force) {
        Write-Warning "Task '$TaskName' already exists (state: $($existing.State))"
        $confirm = Read-Host "Overwrite? (y/N)"
        if ($confirm -ne "y") { Write-Host "Cancelled."; exit 0 }
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed existing task."
}

# ============================================================
# Build task components
# ============================================================
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$WatchdogScriptPath`""

$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) `
    -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes)

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

if ($UseSystem) {
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
}

# ============================================================
# Register
# ============================================================
Register-ScheduledTask `
    -TaskName $TaskName `
    -Description "OpenClaw Gateway Watchdog - auto-detect and restart gateway" `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Principal $principal

Write-Host ""
Write-Host "Deployed successfully!" -ForegroundColor Green
Write-Host "  Task name : $TaskName"
Write-Host "  Interval  : Every $IntervalMinutes minutes"
Write-Host "  Run as    : $(if ($UseSystem) { 'SYSTEM' } else { $env:USERNAME })"
Write-Host "  Script    : $WatchdogScriptPath"
Write-Host ""
Write-Host "Management commands:"
Write-Host "  Status : Get-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Start  : Start-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Stop   : Stop-ScheduledTask -TaskName '$TaskName'"
Write-Host "  Remove : Unregister-ScheduledTask -TaskName '$TaskName'"
