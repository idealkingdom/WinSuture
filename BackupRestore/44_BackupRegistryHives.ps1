param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true if no registry backup exists in the shared folder or from the last 12 hours
    $backupDir = $global:WinSutureBackupDir
    if ($null -ne $backupDir -and (Test-Path (Join-Path $backupDir "Backup_HKCU.reg"))) {
        return $false
    }
    
    $desktop = [Environment]::GetFolderPath("Desktop")
    $backups = Get-ChildItem -Path $desktop -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue
    if (-not $backups) { return $true }
    
    foreach ($b in $backups) {
        $age = (Get-Date) - $b.CreationTime
        if ($age.TotalHours -lt 12) {
            $hkcu = Join-Path $b.FullName "Backup_HKCU.reg"
            $system = Join-Path $b.FullName "Backup_HKLM_SYSTEM.reg"
            if ((Test-Path $hkcu) -and (Test-Path $system)) {
                return $false
            }
        }
    }
    return $true
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Exporting Registry Hives (HKCU, SOFTWARE, SYSTEM)..."
    
    # Establish shared backup folder for the current run session
    if ($null -eq $global:WinSutureBackupDir) {
        $desktop = [Environment]::GetFolderPath("Desktop")
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $global:WinSutureBackupDir = Join-Path $desktop "WinSuture_Backup_$timestamp"
    }
    $backupDir = $global:WinSutureBackupDir
    
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        reg.exe export HKCU "$backupDir\Backup_HKCU.reg" /y | Out-Null
        reg.exe export HKLM\SOFTWARE "$backupDir\Backup_HKLM_SOFTWARE.reg" /y | Out-Null
        reg.exe export HKLM\SYSTEM "$backupDir\Backup_HKLM_SYSTEM.reg" /y | Out-Null
        Write-Host "[+] Registry hives backed up to: $backupDir" -ForegroundColor Green
    } catch {
        Write-Error "Failed to export registry hives: $_"
    }
}
