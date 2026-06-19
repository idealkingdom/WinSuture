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
    # Scan logic: returns $true if at least one system restore point exists to launch from
    try {
        $points = @(Get-RestorePointsSafe)
        if ($null -ne $points -and $points.Count -gt 0) {
            return $true
        }
        return $false
    } catch {
        return $false
    }
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Launching native Windows System Restore UI (rstrui.exe)..."
    try {
        Start-Process "rstrui.exe"
        Write-Host "[+] System Restore interface initiated. Please follow the instructions on-screen." -ForegroundColor Green
    } catch {
        Write-Error "Could not start rstrui.exe: $_"
    }
}
