<#
.SYNOPSIS
    Install Claude Code notification hooks.
.DESCRIPTION
    Merges notification hooks into ~/.claude/settings.json so that
    Claude Code sends Windows desktop toast notifications on Stop,
    Notification, and StopFailure events.

    Safe to run multiple times — existing settings are preserved and
    a backup is created before any changes.
#>

$ErrorActionPreference = "Stop"

# ── Configuration ────────────────────────────────────────────────────
$repoBaseUrl  = "https://raw.githubusercontent.com/Guoan-Tang/Claude-Code-Notification/main"
$notifyUrl    = "$repoBaseUrl/scripts/notify.ps1"

# ── Paths ────────────────────────────────────────────────────────────
$destDir      = Join-Path $env:USERPROFILE "scripts"
$destScript   = Join-Path $destDir "notify.ps1"
$notifyScript = $destScript -replace '\\', '/'
$claudeDir    = Join-Path $env:USERPROFILE ".claude"
$settingsFile = Join-Path $claudeDir "settings.json"

# ── Download notify.ps1 to $USERPROFILE/scripts ─────────────────────
if (-not (Test-Path $destDir)) {
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
    Write-Host "Created $destDir" -ForegroundColor Gray
}

# Use local copy if running from the repo, otherwise download from GitHub
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "scripts\notify.ps1"))) {
    $localSource = Join-Path $PSScriptRoot "scripts\notify.ps1"
    Copy-Item $localSource $destScript -Force
    Write-Host "Deployed notify.ps1 from local repo to $destScript" -ForegroundColor Gray
} else {
    Write-Host "Downloading notify.ps1 from GitHub..." -ForegroundColor Gray
    try {
        Invoke-WebRequest -Uri $notifyUrl -OutFile $destScript -UseBasicParsing
        Write-Host "Downloaded notify.ps1 to $destScript" -ForegroundColor Gray
    } catch {
        Write-Host "ERROR: Failed to download notify.ps1 from $notifyUrl" -ForegroundColor Red
        Write-Host "       $_" -ForegroundColor Red
        exit 1
    }
}

# ── Hook command ─────────────────────────────────────────────────────
$hookCommand = "pwsh.exe -ExecutionPolicy Bypass -File `"$notifyScript`""

# ── Build our hook entries ───────────────────────────────────────────
$hookEvents = @("Stop", "Notification", "StopFailure")

function New-HookEntry([string]$Command) {
    return @{
        hooks = @(
            @{
                type    = "command"
                command = $Command
                timeout = 10
            }
        )
    }
}

# ── Read existing settings ───────────────────────────────────────────
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    Write-Host "Created $claudeDir" -ForegroundColor Gray
}

$settings = $null
if (Test-Path $settingsFile) {
    $raw = Get-Content $settingsFile -Raw -ErrorAction SilentlyContinue
    if ($raw) {
        $settings = $raw | ConvertFrom-Json

        # Backup before modifying
        $backupFile = "$settingsFile.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        Copy-Item $settingsFile $backupFile
        Write-Host "Backup saved to $backupFile" -ForegroundColor Gray
    }
}

if (-not $settings) {
    $settings = New-Object PSObject
}

# ── Ensure hooks object exists ───────────────────────────────────────
if (-not ($settings | Get-Member -Name hooks -MemberType NoteProperty)) {
    $settings | Add-Member -NotePropertyName hooks -NotePropertyValue (New-Object PSObject)
}

# ── Merge each event ────────────────────────────────────────────────
foreach ($event in $hookEvents) {
    $newEntry = New-HookEntry $hookCommand

    if ($settings.hooks | Get-Member -Name $event -MemberType NoteProperty) {
        # Event key already exists — check if our hook is already present
        $existing = @($settings.hooks.$event)
        $alreadyInstalled = $false

        for ($i = 0; $i -lt $existing.Count; $i++) {
            foreach ($h in $existing[$i].hooks) {
                if ($h.command -like "*notify.ps1*") {
                    # Update in place
                    $h.command = $hookCommand
                    $alreadyInstalled = $true
                }
            }
        }

        if (-not $alreadyInstalled) {
            $settings.hooks.$event = @($existing) + @($newEntry)
        }
    } else {
        $settings.hooks | Add-Member -NotePropertyName $event -NotePropertyValue @($newEntry)
    }
}

# ── Write settings ───────────────────────────────────────────────────
$json = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText($settingsFile, $json, [System.Text.UTF8Encoding]::new($false))

# ── Report ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Successfully installed Claude Code notification hooks!" -ForegroundColor Green
Write-Host ""
Write-Host "  Events : Stop, Notification, StopFailure" -ForegroundColor Cyan
Write-Host "  Script : $notifyScript" -ForegroundColor Cyan
Write-Host "  Config : $settingsFile" -ForegroundColor Cyan
Write-Host ""
Write-Host "Restart Claude Code for changes to take effect." -ForegroundColor Yellow
