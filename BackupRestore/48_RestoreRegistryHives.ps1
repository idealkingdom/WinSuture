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
    $baseDir = "$env:SystemDrive\WinSuture\Backups"
        if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
}

if ($Mode -eq "Check") {
    # Scan logic: returns $true if there is at least one backup folder in the base directory
    $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue
    if ($null -ne $backups -and $backups.Count -gt 0) {
        return $true
    }
    return $false
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Registry Hive Restoration..."
    $targetDir = ""
    if ($null -ne $global:WinSutureRestoreFolder -and (Test-Path $global:WinSutureRestoreFolder)) {
        $targetDir = $global:WinSutureRestoreFolder
        Write-Host "[+] Using selected restore folder: $targetDir" -ForegroundColor Green
    } else {
        $backups = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        if (-not $backups -or $backups.Count -eq 0) {
            Write-Host "[-] No backup folders found in the script directory." -ForegroundColor Red
            $manualPath = Read-Host "Please enter the absolute path to your backup directory (or leave empty to cancel)"
            if ([string]::IsNullOrWhiteSpace($manualPath)) { return }
            $targetDir = $manualPath
        } else {
            Write-Host "Found the following registry backups in the script directory:" -ForegroundColor Yellow
            for ($i = 0; $i -lt $backups.Count; $i++) {
                Write-Host "  [$i] $($backups[$i].Name) (Created: $($backups[$i].CreationTime))" -ForegroundColor White
            }
            Write-Host ""
            $selection = Read-Host "Choose the index of the backup you want to restore (or enter absolute path, or leave empty to cancel)"
            if ([string]::IsNullOrWhiteSpace($selection)) { return }
            
            if ($selection -match '^\d+$' -and [int]$selection -lt $backups.Count) {
                $targetDir = $backups[[int]$selection].FullName
            } else {
                $targetDir = $selection
            }
        }
    }
    
    if (-not (Test-Path $targetDir)) {
        Write-Host "[-] Error: Specified path '$targetDir' does not exist." -ForegroundColor Red
        return
    }
    
    $hkcu = Join-Path $targetDir "Backup_HKCU.reg"
    $software = Join-Path $targetDir "Backup_HKLM_SOFTWARE.reg"
    $system = Join-Path $targetDir "Backup_HKLM_SYSTEM.reg"
    
    Write-Host "[*] Importing registry files from $targetDir..." -ForegroundColor Yellow
    
    $imported = 0
    if (Test-Path $hkcu) {
        Write-Host "  Importing HKCU registry settings..."
        try {
            reg.exe import $hkcu | Out-Null
            $imported++
        } catch {
            Write-Warning "Failed to import HKCU registry settings: $_"
        }
    }
    if (Test-Path $software) {
        Write-Host "  Importing HKLM\SOFTWARE registry settings..."
        try {
            reg.exe import $software | Out-Null
            $imported++
        } catch {
            Write-Warning "Failed to import HKLM\SOFTWARE registry settings: $_"
        }
    }
    if (Test-Path $system) {
        Write-Host "  Importing HKLM\SYSTEM registry settings..."
        try {
            reg.exe import $system | Out-Null
            $imported++
        } catch {
            Write-Warning "Failed to import HKLM\SYSTEM registry settings: $_"
        }
    }
    
    if ($imported -gt 0) {
        Write-Host "[+] Restored $imported registry hive file(s) successfully!" -ForegroundColor Green
        Write-Host "[*] Note: A reboot is highly recommended to apply changes to software/system registry hives." -ForegroundColor Yellow
    } else {
        Write-Host "[-] No backup files (Backup_HKCU.reg, Backup_HKLM_SOFTWARE.reg, Backup_HKLM_SYSTEM.reg) were found in '$targetDir'." -ForegroundColor Red
    }
}
