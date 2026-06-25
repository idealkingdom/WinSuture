param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true if no network config backup exists in the shared folder or from the last 12 hours
    $backupDir = $global:WinSutureBackupDir
    if ($null -ne $backupDir -and (Test-Path (Join-Path $backupDir "Network_IP_Config.txt"))) {
        return $false
    }
    
    $baseDir = $PSScriptRoot
    if ($null -ne $global:WinSutureScriptRoot) {
        $baseDir = $global:WinSutureScriptRoot
    } elseif ($baseDir -like "*BackupRestore") {
        $baseDir = Split-Path -Path $baseDir -Parent
    }
    if ($null -eq $baseDir -or $baseDir -eq "") {
        $baseDir = "$env:SystemDrive\WinSuture\Backups"
        if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
    }
    
    $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue
    foreach ($b in $backups) {
        $age = (Get-Date) - $b.CreationTime
        if ($age.TotalHours -lt 12 -and (Test-Path (Join-Path $b.FullName "Network_IP_Config.txt"))) {
            return $false
        }
    }
    return $true
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Logging active TCP/IP stack configuration..."
    
    # Establish shared backup folder for the current run session
    if ($null -eq $global:WinSutureBackupDir) {
        $baseDir = $PSScriptRoot
        if ($null -ne $global:WinSutureScriptRoot) {
            $baseDir = $global:WinSutureScriptRoot
        } elseif ($baseDir -like "*BackupRestore") {
            $baseDir = Split-Path -Path $baseDir -Parent
        }
        if ($null -eq $baseDir -or $baseDir -eq "") {
            $baseDir = "$env:SystemDrive\WinSuture\Backups"
        if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $global:WinSutureBackupDir = Join-Path $baseDir "WinSuture_Backup_$timestamp"
    }
    $backupDir = $global:WinSutureBackupDir
    
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        Get-NetIPAddress | Out-File "$backupDir\Network_IP_Config.txt" -Force
        Get-DnsClientServerAddress | Out-File "$backupDir\Network_DNS_Config.txt" -Force
        Get-NetRoute | Out-File "$backupDir\Network_Routing_Table.txt" -Force
        Write-Host "[+] Network configurations logged to: $backupDir" -ForegroundColor Green
    } catch {
        Write-Warning "Network properties log failed: $_"
    }
}
