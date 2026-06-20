param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

$hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"

if ($Mode -eq "Check") {
    # Scan logic: returns $true if no hosts.bak exists in the shared folder or from the last 12 hours
    $backupDir = $global:WinSutureBackupDir
    if ($null -ne $backupDir -and (Test-Path (Join-Path $backupDir "hosts.bak"))) {
        return $false
    }
    
    $baseDir = $PSScriptRoot
    if ($null -ne $global:WinSutureScriptRoot) {
        $baseDir = $global:WinSutureScriptRoot
    } elseif ($baseDir -like "*BackupRestore") {
        $baseDir = Split-Path -Path $baseDir -Parent
    }
    if ($null -eq $baseDir -or $baseDir -eq "") {
        $baseDir = Get-Location
    }
    
    $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue
    foreach ($b in $backups) {
        $age = (Get-Date) - $b.CreationTime
        if ($age.TotalHours -lt 12 -and (Test-Path (Join-Path $b.FullName "hosts.bak"))) {
            return $false
        }
    }
    return $true
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Backing up system hosts configuration..."
    
    # Establish shared backup folder for the current run session
    if ($null -eq $global:WinSutureBackupDir) {
        $baseDir = $PSScriptRoot
        if ($null -ne $global:WinSutureScriptRoot) {
            $baseDir = $global:WinSutureScriptRoot
        } elseif ($baseDir -like "*BackupRestore") {
            $baseDir = Split-Path -Path $baseDir -Parent
        }
        if ($null -eq $baseDir -or $baseDir -eq "") {
            $baseDir = Get-Location
        }
        
        $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
        $global:WinSutureBackupDir = Join-Path $baseDir "WinSuture_Backup_$timestamp"
    }
    $backupDir = $global:WinSutureBackupDir
    
    if (-not (Test-Path $backupDir)) {
        New-Item -Path $backupDir -ItemType Directory -Force | Out-Null
    }
    
    if (Test-Path $hostsPath) {
        try {
            Copy-Item -Path $hostsPath -Destination "$backupDir\hosts.bak" -Force -ErrorAction Stop
            Write-Host "[+] hosts file copied to: $backupDir\hosts.bak" -ForegroundColor Green
        } catch {
            Write-Warning "hosts file copy failed: $_"
        }
    } else {
        Write-Warning "System hosts file not found at $hostsPath."
    }
}
