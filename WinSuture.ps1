# Force console output encoding to UTF-8 to display Unicode characters correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Check for Administrator elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] Error: WinSuture must be run in an elevated PowerShell session!" -ForegroundColor Red
    Write-Host "[*] Please open PowerShell as Administrator and run the command again." -ForegroundColor Yellow
    Exit
}

# --- CONFIGURATION ---
$githubBaseUrl = "https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main"

# Safe Mode detection (SAFEBOOT environment variable is present in Safe Mode)
$isSafeMode = $null -ne [System.Environment]::GetEnvironmentVariable("SAFEBOOT")

if (-not $isSafeMode) {
    Clear-Host
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host "                                   !!! WARNING !!!                                      " -ForegroundColor Red
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host " WinSuture is currently running in Windows Normal Mode." -ForegroundColor Yellow
    Write-Host ""
    Write-Host " It is STRONGLY RECOMMENDED to run this tool in SAFE MODE." -ForegroundColor White
    Write-Host ""
    Write-Host " Why Safe Mode?" -ForegroundColor Cyan
    Write-Host " 1. Prevents active processes and antivirus engines from blocking registry writes." -ForegroundColor Gray
    Write-Host " 2. Avoids file locks when resetting caches or rebuilding components." -ForegroundColor Gray
    Write-Host " 3. Ensures system mending operations execute with maximum success rates." -ForegroundColor Gray
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host ""
    $response = Read-Host " Do you want to proceed in Normal Mode anyway? (Y/N)"
    if ($response.Trim().ToUpper() -ne 'Y') {
        Write-Host ""
        Write-Host "[*] Exiting. Please reboot your system into Safe Mode and run WinSuture again." -ForegroundColor Green
        Exit
    }
}

# --- HELPER FUNCTIONS ---

# Helper to load a tweak's unified scriptblock (sourcing from local relative directory or GitHub raw fallback)
function Get-TweakScript {
    param(
        [Parameter(Mandatory=$true)]
        $item
    )
    
    # Check for local file path relative to the directory of this loader script
    $localPath = Join-Path $PSScriptRoot $item.Path
    if (Test-Path $localPath) {
        try {
            $code = Get-Content -Path $localPath -Raw -ErrorAction Stop
            return [scriptblock]::Create($code)
        } catch {
            Write-Warning "Failed to read local file '$localPath'. Attempting cloud fallback..."
        }
    }
    
    # Fallback to downloading raw script from GitHub raw URL
    $cloudUrl = "$githubBaseUrl/$($item.Path)"
    try {
        $code = Invoke-RestMethod -Uri $cloudUrl -ErrorAction Stop
        return [scriptblock]::Create($code)
    } catch {
        Write-Error "Failed to load script block from local path or cloud URL: $cloudUrl"
        return $null
    }
}

# Helper to load a manifest file with local path and fallback to cloud
function Load-ManifestFile {
    param(
        [string]$filename
    )
    $localPath = Join-Path $PSScriptRoot $filename
    $data = $null
    
    if (Test-Path $localPath) {
        try {
            $json = Get-Content -Path $localPath -Raw -ErrorAction Stop
            $data = ConvertFrom-Json $json
        } catch {
            Write-Warning "Failed to read local $filename. Attempting cloud download fallback..."
        }
    }
    
    if ($null -eq $data) {
        $cloudUrl = "$githubBaseUrl/$filename"
        try {
            $json = Invoke-RestMethod -Uri $cloudUrl -ErrorAction Stop
            $data = ConvertFrom-Json $json
        } catch {
            Write-Host "[-] Critical Error: Failed to load manifest file '$filename' locally or from $cloudUrl" -ForegroundColor Red
            Write-Host "[-] Please check your internet connection or verify your \$githubBaseUrl path." -ForegroundColor Yellow
            Pause
            Exit
        }
    }
    return $data
}

# Load the three distinct manifest JSON files
$opts = Load-ManifestFile -filename "optimizations.json"
$reps = Load-ManifestFile -filename "repairs.json"
$backups = Load-ManifestFile -filename "backuprestore.json"

# Combine into a single tweaks database array for menu controls, tracking, and executing
$tweaks = @()
$tweaks += $opts
$tweaks += $reps
$tweaks += $backups

# Initialize runtime tracking members on all loaded manifest objects
foreach ($t in $tweaks) {
    $t | Add-Member -MemberType NoteProperty -Name "Selected" -Value $false -Force
    $t | Add-Member -MemberType NoteProperty -Name "ScanStatus" -Value "" -Force
}

# Helper to structure items under their subcategory subheaders
function Get-LayoutLines {
    param(
        [array]$items
    )
    $lines = @()
    if ($null -eq $items -or $items.Count -eq 0) {
        return $lines
    }
    
    $grouped = $items | Group-Object Subcategory
    foreach ($g in $grouped) {
        # Add a subcategory header line
        $lines += [PSCustomObject]@{
            Type = "Header"
            Text = $g.Name
        }
        foreach ($item in $g.Group) {
            # Add the item itself
            $lines += [PSCustomObject]@{
                Type = "Item"
                Item = $item
            }
        }
    }
    return $lines
}

# Custom header renderer
function Draw-Header {
    param([string]$subtitle = "")
    Clear-Host
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host "                                WIN SUTURE POWER CLI TOOL                               " -ForegroundColor White
    Write-Host "========================================================================================" -ForegroundColor Cyan
    if (-not $isSafeMode) {
        Write-Host "  ⚠️  RECOMMENDED: Run WinSuture in Safe Mode to avoid file locks and service conflicts." -ForegroundColor Yellow
        Write-Host "========================================================================================" -ForegroundColor Cyan
    } else {
        Write-Host "  🛡️  STATUS: Running in Safe Mode (Minimal/Network). System mending optimal." -ForegroundColor Green
        Write-Host "========================================================================================" -ForegroundColor Cyan
    }
    if ($subtitle) {
        Write-Host "  $subtitle" -ForegroundColor Yellow
        Write-Host "========================================================================================" -ForegroundColor Cyan
    }
}

# Main input loop
$alertMessage = ""
$alertColor = "Yellow"

while ($true) {
    Draw-Header -subtitle "Presets: P1 (Basic Opts) | P2 (Advanced Opts) | P3 (System Repairs) | C (Clear All)"
    
    # Generate left and right column layout lines dynamically
    $optLines = Get-LayoutLines -items $opts
    $repLines = Get-LayoutLines -items $reps
    
    # Print the options in a side-by-side 2-column layout
    $leftWidth = 46
    $maxRows = [Math]::Max($optLines.Count, $repLines.Count)
    for ($i = 0; $i -lt $maxRows; $i++) {
        $opt = if ($i -lt $optLines.Count) { $optLines[$i] } else { $null }
        $rep = if ($i -lt $repLines.Count) { $repLines[$i] } else { $null }
        
        # Format left column
        $optText = ""
        $optColor = "Gray"
        if ($null -ne $opt) {
            if ($opt.Type -eq "Header") {
                $optText = " -- $($opt.Text) --"
                $optColor = "Cyan"
            }
            elseif ($opt.Type -eq "Item") {
                $item = $opt.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $optText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $optColor = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $optColor = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $optColor = "Red" }
            }
        }
        
        # Format right column
        $repText = ""
        $repColor = "Gray"
        if ($null -ne $rep) {
            if ($rep.Type -eq "Header") {
                $repText = " -- $($rep.Text) --"
                $repColor = "Cyan"
            }
            elseif ($rep.Type -eq "Item") {
                $item = $rep.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $repText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $repColor = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $repColor = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $repColor = "Red" }
            }
        }
        
        # Render side-by-side
        Write-Host $optText.PadRight($leftWidth) -NoNewline -ForegroundColor $optColor
        Write-Host " | " -NoNewline -ForegroundColor Cyan
        Write-Host $repText -ForegroundColor $repColor
    }
    
    Write-Host "----------------------------------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "                                   BACKUP & RESTORE                                     " -ForegroundColor White
    Write-Host "----------------------------------------------------------------------------------------" -ForegroundColor Cyan
    
    # Generate backups and restores layout lines dynamically
    $bkpOpts = $backups | Where-Object { $_.Subcategory -eq "System Backups" }
    $rstOpts = $backups | Where-Object { $_.Subcategory -eq "System Restores" }
    
    $bkpLines = Get-LayoutLines -items $bkpOpts
    $rstLines = Get-LayoutLines -items $rstOpts
    
    $maxBkpRows = [Math]::Max($bkpLines.Count, $rstLines.Count)
    for ($i = 0; $i -lt $maxBkpRows; $i++) {
        $bkp1 = if ($i -lt $bkpLines.Count) { $bkpLines[$i] } else { $null }
        $bkp2 = if ($i -lt $rstLines.Count) { $rstLines[$i] } else { $null }
        
        # Format left column (Backups)
        $bkp1Text = ""
        $bkp1Color = "Gray"
        if ($null -ne $bkp1) {
            if ($bkp1.Type -eq "Header") {
                $bkp1Text = " -- $($bkp1.Text) --"
                $bkp1Color = "Cyan"
            }
            elseif ($bkp1.Type -eq "Item") {
                $item = $bkp1.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $bkp1Text = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $bkp1Color = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $bkp1Color = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $bkp1Color = "Red" }
            }
        }
        
        # Format right column (Restores)
        $bkp2Text = ""
        $bkp2Color = "Gray"
        if ($null -ne $bkp2) {
            if ($bkp2.Type -eq "Header") {
                $bkp2Text = " -- $($bkp2.Text) --"
                $bkp2Color = "Cyan"
            }
            elseif ($bkp2.Type -eq "Item") {
                $item = $bkp2.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $bkp2Text = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $bkp2Color = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $bkp2Color = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $bkp2Color = "Red" }
            }
        }
        
        # Render side-by-side
        Write-Host $bkp1Text.PadRight($leftWidth) -NoNewline -ForegroundColor $bkp1Color
        Write-Host " | " -NoNewline -ForegroundColor Cyan
        Write-Host $bkp2Text -ForegroundColor $bkp2Color
    }
    
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host "  Legend: [x] Checked | v Scanned Healthy | * Scanned Recommended | ! Dangerous (Red)" -ForegroundColor DarkGray
    Write-Host "========================================================================================" -ForegroundColor Cyan
    
    if ($alertMessage) {
        Write-Host "  [*] $alertMessage" -ForegroundColor $alertColor
        Write-Host "========================================================================================" -ForegroundColor Cyan
        $alertMessage = ""
    }
    
    # User Input
    Write-Host "  Inputs: <id,id,...> to toggle | P1/P2/P3 for Presets | B to Backup | S to Scan | R to Run | Q to Quit" -ForegroundColor DarkCyan
    $input = Read-Host "  WinSuture CLI"
    $input = $input.Trim().Replace("'", "").Replace('"', "").ToUpper()
    
    $showDesc = $false
    if ($input -match '\s*-D$') {
        $showDesc = $true
        $input = $input -replace '\s*-D$', ''
    }
    
    if ($input -eq "Q") {
        Clear-Host
        Write-Host "[+] Thank you for using WinSuture! Goodbye." -ForegroundColor Green
        exit
    }
    elseif ($input -eq "C") {
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            $tweaks[$i].Selected = $false
        }
        $alertMessage = "All selections cleared."
        $alertColor = "Yellow"
    }
    elseif ($input -eq "P1") {
        # Toggle Basic optimizations preset
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Packages -contains "Basic") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Basic Optimizations Preset (P1)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P2") {
        # Toggle Advanced optimizations preset
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Packages -contains "Advanced") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Advanced Optimizations Preset (P2)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P3") {
        # Toggle System Repairs preset
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Packages -contains "Repairs") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled System Repairs Preset (P3)."
        $alertColor = "Green"
    }
    elseif ($input -eq "B") {
        Draw-Header -subtitle "Running Consolidated Advanced Backups..."
        # Reset the global backup directory so a fresh folder is created
        $global:WinSutureBackupDir = $null
        
        $backupItems = $tweaks | Where-Object { $_.Id -ge 41 -and $_.Id -le 44 }
        foreach ($item in $backupItems) {
            Write-Host "[*] Executing Task $($item.Id): $($item.Name)..." -ForegroundColor Yellow
            $sb = Get-TweakScript -item $item
            if ($null -ne $sb) {
                try {
                    & $sb -Mode "Apply"
                } catch {
                    Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
                }
            } else {
                Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        $alertMessage = "Advanced Backups Suite complete! Files saved in Desktop folder."
        $alertColor = "Green"
    }
    elseif ($input -eq "S") {
        Write-Host "  [*] Initiating AeroDiagnostics scan for bottlenecks... Please wait..." -ForegroundColor Yellow
        
        $recCount = 0
        $recommendedIds = @()
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            $t = $tweaks[$i]
            $sb = Get-TweakScript -item $t
            if ($null -eq $sb) {
                $tweaks[$i].ScanStatus = "Error"
                continue
            }
            try {
                $needsTweak = & $sb -Mode "Check"
                if ($needsTweak) {
                    $tweaks[$i].ScanStatus = "Recommended"
                    $recommendedIds += $t.Id
                    $recCount++
                } else {
                    $tweaks[$i].ScanStatus = "Healthy"
                }
            } catch {
                $tweaks[$i].ScanStatus = "Error"
            }
        }
        
        Write-Host "  [+] Scan complete! Found $recCount recommended improvements (marked with '*')." -ForegroundColor Yellow
        if ($recCount -gt 0) {
            $preselect = Read-Host "  Would you like to pre-select these $recCount recommendations? (Y/N)"
            if ($preselect.Trim().ToUpper() -eq "Y") {
                foreach ($id in $recommendedIds) {
                    $tweaks[$id - 1].Selected = $true
                }
                $alertMessage = "Scan Complete! Recommended items have been pre-selected (marked with '*')."
            } else {
                $alertMessage = "Scan Complete! Recommendations displayed (marked with '*'), but selection was not changed."
            }
        } else {
            $alertMessage = "Scan Complete! Your system is fully optimized according to the standard checks."
        }
        $alertColor = "Green"
    }
    elseif ($input -eq "R") {
        # Filter checked items
        $selectedItems = $tweaks | Where-Object { $_.Selected -eq $true }
        
        if ($selectedItems.Count -eq 0) {
            $alertMessage = "No items selected to run. Please select items first!"
            $alertColor = "Red"
            continue
        }
        
        # Check for dangerous items
        $dangerousItems = $selectedItems | Where-Object { $_.Danger -eq "Dangerous" }
        
        if ($dangerousItems.Count -gt 0) {
            Draw-Header -subtitle "⚠️ SYSTEM CHANGE DANGER WARNING ⚠️"
            Write-Host "You have selected modifications with a HIGH RISK profile:" -ForegroundColor Red
            Write-Host ""
            foreach ($dt in $dangerousItems) {
                Write-Host "  * Item $($dt.Id): $($dt.Name)" -ForegroundColor Red
                Write-Host "    $($dt.Description)" -ForegroundColor DarkRed
                Write-Host ""
            }
            Write-Host "Applying dangerous tweaks may reduce system security layers (like Memory Integrity) or" -ForegroundColor Yellow
            Write-Host "alter boot databases. Please double check that you want these applied." -ForegroundColor Yellow
            Write-Host ""
            $confirm = Read-Host "Are you absolutely sure you want to run these high-risk actions? (Type 'CONFIRM')"
            if ($confirm -ne "CONFIRM") {
                $alertMessage = "Action execution aborted by user."
                $alertColor = "Yellow"
                continue
            }
        }
        
        # Check if explorer restart or reboot is required
        $hasExplorerRestart = $selectedItems | Where-Object { $_.RequiresExplorerRestart -eq $true }
        $hasReboot = $selectedItems | Where-Object { $_.RequiresReboot -eq $true }
        
        if ($hasExplorerRestart -or $hasReboot) {
            Draw-Header -subtitle "System Operations Warning"
            Write-Host "⚠️  ATTENTION - SYSTEM EFFECT ACTIONS DETECTED:" -ForegroundColor Yellow
            Write-Host "========================================================================================" -ForegroundColor Cyan
            if ($hasExplorerRestart) {
                Write-Host "  * Windows Explorer will restart automatically (flashing your screen/taskbar briefly)." -ForegroundColor Yellow
                foreach ($item in $hasExplorerRestart) {
                    Write-Host "    - Item $($item.Id): $($item.Name)" -ForegroundColor Gray
                }
            }
            if ($hasReboot) {
                if ($hasExplorerRestart) { Write-Host "" }
                Write-Host "  * A computer reboot is required to fully activate the following configurations:" -ForegroundColor Yellow
                foreach ($item in $hasReboot) {
                    Write-Host "    - Item $($item.Id): $($item.Name)" -ForegroundColor Gray
                }
            }
            Write-Host "========================================================================================" -ForegroundColor Cyan
            $proceed = Read-Host "  Do you want to proceed with executing these tasks? (Y/N)"
            if ($proceed.ToUpper() -ne "Y") {
                $alertMessage = "Action execution aborted by user."
                $alertColor = "Yellow"
                continue
            }
        }
        
        # Execute runner
        Draw-Header -subtitle "Running System Tasks..."
        
        # Create Restore Point before executing
        Write-Host "[*] Initiating pre-run safety checkpoints..." -ForegroundColor Yellow
        try {
            Checkpoint-Computer -Description "WinSutureRun" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
            Write-Host "[+] Pre-run Restore Point created successfully!" -ForegroundColor Green
        } catch {
            Write-Host "[-] Warning: System Protection is disabled or Restore Point rate-limit reached. Proceeding anyway." -ForegroundColor Yellow
        }
        Write-Host ""
        
        # Sort selected items: Backups (43-46) must run first!
        $sortedItems = @()
        $sortedItems += $selectedItems | Where-Object { $_.Id -ge 43 -and $_.Id -le 46 }
        $sortedItems += $selectedItems | Where-Object { $_.Id -lt 43 -or $_.Id -gt 46 }
        
        foreach ($item in $sortedItems) {
            Write-Host "[*] Executing Task $($item.Id): $($item.Name)..." -ForegroundColor Yellow
            $sb = Get-TweakScript -item $item
            if ($null -eq $sb) {
                Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
                continue
            }
            try {
                & $sb -Mode "Apply"
                Write-Host "    [SUCCESS]" -ForegroundColor Green
            } catch {
                Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
            }
            Write-Host ""
        }
        
        Write-Host "========================================================================================" -ForegroundColor Cyan
        Write-Host "  All selected tasks completed!" -ForegroundColor Green
        Write-Host "  Note: Some registry, service, and layout optimizations require you to restart" -ForegroundColor Yellow
        Write-Host "  Windows Explorer (or reboot your PC) to take full effect." -ForegroundColor Yellow
        Write-Host "========================================================================================" -ForegroundColor Cyan
        Pause
    }
    else {
        # Check if numbers input
        $indices = $input -split ","
        
        if ($showDesc) {
            $descItems = @()
            foreach ($indexStr in $indices) {
                $cleanStr = $indexStr.Trim()
                if ($cleanStr -match '^\d+$') {
                    $cleanIdx = [int]$cleanStr
                    if ($cleanIdx -ge 1 -and $cleanIdx -le $tweaks.Count) {
                        $descItems += $tweaks[$cleanIdx - 1]
                    }
                }
            }
            
            if ($descItems.Count -gt 0) {
                Draw-Header -subtitle "Tweak / Repair Description Help"
                foreach ($item in $descItems) {
                    $dangerColor = if ($item.Danger -eq "Dangerous") { "Red" } else { "Green" }
                    Write-Host "Item $($item.Id): $($item.Name)" -ForegroundColor Yellow
                    Write-Host "  Category:    $($item.Category)" -ForegroundColor Gray
                    Write-Host "  Danger:      [$($item.Danger)]" -ForegroundColor $dangerColor
                    Write-Host "  Description: $($item.Description)" -ForegroundColor White
                    Write-Host ""
                }
                Write-Host "========================================================================================" -ForegroundColor Cyan
                Pause
                continue
            } else {
                $alertMessage = "No valid item IDs found to describe."
                $alertColor = "Red"
            }
        }
        else {
            $successCount = 0
            foreach ($indexStr in $indices) {
                $cleanStr = $indexStr.Trim()
                if ($cleanStr -match '^\d+$') {
                    $cleanIdx = [int]$cleanStr
                    if ($cleanIdx -ge 1 -and $cleanIdx -le $tweaks.Count) {
                        # Toggle selection
                        $tweaks[$cleanIdx - 1].Selected = -not $tweaks[$cleanIdx - 1].Selected
                        $successCount++
                    }
                }
            }
            
            if ($successCount -eq 0) {
                $alertMessage = "Invalid command or selection index: '$input'"
                $alertColor = "Red"
            } else {
                $alertMessage = "Toggled $successCount item(s)."
                $alertColor = "Green"
            }
        }
    }
}
