param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true if at least one system restore point exists to launch from
    try {
        $points = Get-ComputerRestorePoint -ErrorAction SilentlyContinue
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
