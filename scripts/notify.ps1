<#
.SYNOPSIS
    Send a Windows Toast notification for Claude Code hook events.
.DESCRIPTION
    Called by Claude Code hooks (Stop, Notification, StopFailure).
    Reads JSON from stdin, determines event type, and sends a
    Windows desktop toast notification so you never miss an instance
    finishing or needing approval.
#>

# ── Read hook data from stdin ────────────────────────────────────────
$jsonText = @($input) -join "`n"

$hookData = $null
if ($jsonText) {
    try { $hookData = $jsonText | ConvertFrom-Json } catch { }
}

# ── Extract context ──────────────────────────────────────────────────
$eventName        = if ($hookData -and $hookData.hook_event_name)  { $hookData.hook_event_name }  else { "Unknown" }
$cwd              = if ($hookData -and $hookData.cwd)              { $hookData.cwd }              else { "" }
$notificationType = if ($hookData -and $hookData.notification_type){ $hookData.notification_type } else { "" }
$sessionId        = if ($hookData -and $hookData.session_id)       { $hookData.session_id }       else { "" }

$projectName = if ($cwd) { Split-Path $cwd -Leaf } else { "Unknown" }

# ── Build notification title & message ───────────────────────────────
switch ($eventName) {
    "Stop" {
        $title   = "Claude Code - Done"
        $message = "Finished responding in [$projectName]"
    }
    "Notification" {
        switch ($notificationType) {
            "permission_prompt" {
                $title   = "Claude Code - Approval Needed"
                $message = "Waiting for your approval in [$projectName]"
            }
            "idle_prompt" {
                $title   = "Claude Code - Input Needed"
                $message = "Waiting for your input in [$projectName]"
            }
            default {
                $title   = "Claude Code - Attention"
                $message = "Needs your attention in [$projectName]"
            }
        }
    }
    "StopFailure" {
        $title   = "Claude Code - Error"
        $message = "An error occurred in [$projectName]"
    }
    default {
        $title   = "Claude Code"
        $message = "Event [$eventName] in [$projectName]"
    }
}

# ── Send Windows Toast Notification ──────────────────────────────────
function Send-ToastNotification {
    param([string]$Title, [string]$Message)

    # Load WinRT assemblies (Windows PowerShell 5.1)
    $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime]

    $escapedTitle   = [System.Security.SecurityElement]::Escape($Title)
    $escapedMessage = [System.Security.SecurityElement]::Escape($Message)

    $toastXml = @"
<toast duration="short">
    <visual>
        <binding template="ToastGeneric">
            <text>$escapedTitle</text>
            <text>$escapedMessage</text>
        </binding>
    </visual>
    <audio src="ms-winsoundevent:Notification.Default"/>
</toast>
"@

    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)

    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)

    # PowerShell's registered AppUserModelID — always available on Windows
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show($toast)
}

function Send-BalloonNotification {
    param([string]$Title, [string]$Message)

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $balloon            = New-Object System.Windows.Forms.NotifyIcon
    $balloon.Icon       = [System.Drawing.SystemIcons]::Information
    $balloon.BalloonTipTitle = $Title
    $balloon.BalloonTipText  = $Message
    $balloon.BalloonTipIcon  = [System.Windows.Forms.ToolTipIcon]::Info
    $balloon.Visible    = $true
    $balloon.ShowBalloonTip(5000)

    # Register dispose on balloon closed so it cleans up
    Register-ObjectEvent -InputObject $balloon -EventName BalloonTipClosed -Action {
        $balloon.Dispose()
    } | Out-Null

    # Keep alive briefly so the OS can render the balloon
    Start-Sleep -Milliseconds 500
}

# Try modern Toast API first, fall back to legacy balloon
try {
    Send-ToastNotification -Title $title -Message $message
} catch {
    try {
        Send-BalloonNotification -Title $title -Message $message
    } catch {
        Write-Error "Failed to send notification: $title - $message"
    }
}

exit 0
