param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

$baseDir = $PSScriptRoot
if ($null -ne $global:WinSutureScriptRoot) {
    $baseDir = $global:WinSutureScriptRoot
} elseif ($baseDir -like "*BackupRestore") {
    $baseDir = Split-Path -Path $baseDir -Parent
}
if ($null -eq $baseDir -or $baseDir -eq "") {
    $baseDir = Get-Location
}

if ($Mode -eq "Check") {
    # Scan logic: returns $true if at least one hosts.bak exists on baseDir folders
    $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue
    foreach ($b in $backups) {
        if (Test-Path (Join-Path $b.FullName "hosts.bak")) {
            return $true
        }
    }
    return $false
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Restoring hosts File from Backup..."
    $targetDir = ""
    if ($null -ne $global:WinSutureRestoreFolder -and (Test-Path $global:WinSutureRestoreFolder)) {
        $targetDir = $global:WinSutureRestoreFolder
        Write-Host "[+] Using selected restore folder: $targetDir" -ForegroundColor Green
    } else {
        $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        $hostsBackups = @()
        foreach ($b in $backups) {
            if (Test-Path (Join-Path $b.FullName "hosts.bak")) {
                $hostsBackups += $b
            }
        }
        
        if ($hostsBackups.Count -eq 0) {
            Write-Host "[-] No backup folders containing 'hosts.bak' were found in the script directory." -ForegroundColor Red
            $manualPath = Read-Host "Please enter the absolute path to your backup directory (or leave empty to cancel)"
            if ([string]::IsNullOrWhiteSpace($manualPath)) { return }
            $targetDir = $manualPath
        } else {
            Write-Host "Found the following hosts backups:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $hostsBackups.Count; $i++) {
                Write-Host "  [$i] $($hostsBackups[$i].Name) (Created: $($hostsBackups[$i].CreationTime))" -ForegroundColor White
            }
            Write-Host ""
            $selection = Read-Host "Choose the index of the hosts backup to restore (or enter absolute path, or leave empty to cancel)"
            if ([string]::IsNullOrWhiteSpace($selection)) { return }
            
            if ($selection -match '^\d+$' -and [int]$selection -lt $hostsBackups.Count) {
                $targetDir = $hostsBackups[[int]$selection].FullName
            } else {
                $targetDir = $selection
            }
        }
    }
    
    if (-not (Test-Path $targetDir)) {
        Write-Host "[-] Error: Specified path '$targetDir' does not exist." -ForegroundColor Red
        return
    }
    
    $bakFile = Join-Path $targetDir "hosts.bak"
    $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
    
    if (Test-Path $bakFile) {
        try {
            # Remove Read-Only attribute if exists
            if (Test-Path $hostsPath) {
                $file = Get-Item -Path $hostsPath -Force
                if ($file.IsReadOnly) {
                    $file.IsReadOnly = $false
                }
            }
            Copy-Item -Path $bakFile -Destination $hostsPath -Force -ErrorAction Stop
            Write-Host "[+] hosts file restored successfully from $bakFile" -ForegroundColor Green
        } catch {
            Write-Error "Failed to restore hosts file: $_"
        }
    } else {
        Write-Host "[-] Error: 'hosts.bak' not found in '$targetDir'." -ForegroundColor Red
    }
}
