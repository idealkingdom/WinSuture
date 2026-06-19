param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

function Get-RestorePointsSafe {
    $points = @()
    if (Get-Command Get-ComputerRestorePoint -ErrorAction SilentlyContinue) {
        try {
            $points = @(Get-ComputerRestorePoint -ErrorAction Stop)
        } catch {
            $points = @()
        }
    }
    if ($points.Count -eq 0) {
        try {
            $points = @(Get-CimInstance -Namespace root/default -ClassName SystemRestore -ErrorAction Stop)
        } catch {
            $points = @()
        }
    }
    $normalized = foreach ($p in $points) {
        $ctime = $p.CreationTime
        if ($ctime -is [string]) {
            if ($ctime -match '^\d{14}\.') {
                try {
                    $ctime = [Management.ManagementDateTimeConverter]::ToDateTime($ctime)
                } catch {
                    try {
                        $ctime = [DateTime]::Parse($ctime)
                    } catch {}
                }
            } else {
                try {
                    $ctime = [DateTime]::Parse($ctime)
                } catch {}
            }
        }
        [PSCustomObject]@{
            SequenceNumber    = $p.SequenceNumber
            Description       = $p.Description
            CreationTime      = $ctime
            RestorePointType  = $p.RestorePointType
            EventType         = $p.EventType
        }
    }
    return $normalized
}

if ($Mode -eq "Check") {
    # Scan logic: returns $true if no restore point exists from the last 24 hours
    try {
        $points = @(Get-RestorePointsSafe)
        if ($null -eq $points -or $points.Count -eq 0) {
            return $true
        }
        $lastPoint = $points | Select-Object -Last 1
        $age = (Get-Date) - $lastPoint.CreationTime
        if ($age.TotalHours -gt 24) {
            return $true
        }
        return $false
    } catch {
        return $true
    }
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Creating Windows System Restore Point..."
    try {
        Checkpoint-Computer -Description "WinSutureBackup" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop
        Write-Host "[+] Restore point created successfully." -ForegroundColor Green
    } catch {
        Write-Warning "Could not create Restore Point. Ensure System Protection is enabled on drive C:."
    }
}
