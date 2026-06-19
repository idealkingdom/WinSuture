param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true if no restore point exists from the last 24 hours
    try {
        $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
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
