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
    # System Backup tasks (IDs 43-46) are enabled by default
    $defaultSelected = ($t.Id -ge 43 -and $t.Id -le 46)
    $t | Add-Member -MemberType NoteProperty -Name "Selected" -Value $defaultSelected -Force
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
    
    # Render Screen Tabs
    if ($script:activeScreen -ne "M") {
        $tabO = if ($script:activeScreen -eq "O") { "[*] OPTIMIZATIONS" } else { "    OPTIMIZATIONS" }
        $tabR = if ($script:activeScreen -eq "R") { "[*] REPAIRS      " } else { "    REPAIRS      " }
        $tabB = if ($script:activeScreen -eq "B") { "[*] BACKUP & REST" } else { "    BACKUP & REST" }
        
        $colorO = if ($script:activeScreen -eq "O") { "Green" } else { "Gray" }
        $colorR = if ($script:activeScreen -eq "R") { "Green" } else { "Gray" }
        $colorB = if ($script:activeScreen -eq "B") { "Green" } else { "Gray" }
        
        Write-Host "  " -NoNewline
        Write-Host $tabO -ForegroundColor $colorO -NoNewline
        Write-Host "  |  " -ForegroundColor Cyan -NoNewline
        Write-Host $tabR -ForegroundColor $colorR -NoNewline
        Write-Host "  |  " -ForegroundColor Cyan -NoNewline
        Write-Host $tabB -ForegroundColor $colorB
        
        Write-Host "========================================================================================" -ForegroundColor Cyan
        if (-not $isSafeMode) {
            Write-Host "  [!] RECOMMENDED: Run WinSuture in Safe Mode to avoid file locks and service conflicts." -ForegroundColor Yellow
            Write-Host "========================================================================================" -ForegroundColor Cyan
        } else {
            Write-Host "  [SAFE] STATUS: Running in Safe Mode (Minimal/Network). System mending optimal." -ForegroundColor Green
            Write-Host "========================================================================================" -ForegroundColor Cyan
        }
    }
    
    if ($subtitle) {
        Write-Host "  $subtitle" -ForegroundColor Yellow
        Write-Host "========================================================================================" -ForegroundColor Cyan
    }
}

# Active screen state: M = Main Menu, O = Optimizations, R = Repairs, B = Backup & Restore
$script:activeScreen = "M"

# Shared task execution function
function Invoke-RunSelected {
    # Filter checked items
    $selectedItems = $tweaks | Where-Object { $_.Selected -eq $true }
    
    if ($selectedItems.Count -eq 0) {
        $script:alertMessage = "No items selected to run. Please select items first!"
        $script:alertColor = "Red"
        return
    }
    
    # Check for dangerous items
    $dangerousItems = $selectedItems | Where-Object { $_.Danger -eq "Dangerous" }
    
    if ($dangerousItems.Count -gt 0) {
        Draw-Header -subtitle "[!] SYSTEM CHANGE DANGER WARNING [!]"
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
            $script:alertMessage = "Action execution aborted by user."
            $script:alertColor = "Yellow"
            return
        }
    }
    
    # Check if explorer restart or reboot is required
    $hasExplorerRestart = $selectedItems | Where-Object { $_.RequiresExplorerRestart -eq $true }
    $hasReboot = $selectedItems | Where-Object { $_.RequiresReboot -eq $true }
    
    if ($hasExplorerRestart -or $hasReboot) {
        Draw-Header -subtitle "System Operations Warning"
        Write-Host "[!] ATTENTION - SYSTEM EFFECT ACTIONS DETECTED:" -ForegroundColor Yellow
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
            $script:alertMessage = "Action execution aborted by user."
            $script:alertColor = "Yellow"
            return
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

# Main input loop
$alertMessage = ""
$alertColor = "Yellow"

while ($true) {
    # If on Main Menu, display it and continue loop
    if ($script:activeScreen -eq "M") {
        Draw-Header
        
        if (-not $isSafeMode) {
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
        }
        
        Write-Host ""
        Write-Host "  Category Screens:" -ForegroundColor Cyan
        Write-Host "    [1] Optimizations (20 Performance Tweaks)" -ForegroundColor White
        Write-Host "    [2] Repairs       (22 Critical System Fixes)" -ForegroundColor White
        Write-Host "    [3] Backup & Rest (8 Backup & Restore Utilities)" -ForegroundColor White
        Write-Host ""
        
        # Calculate selected items count
        $selectedCount = ($tweaks | Where-Object { $_.Selected -eq $true }).Count
        $selectedText = if ($selectedCount -gt 0) { "$selectedCount items selected" } else { "none selected" }
        $selectedColor = if ($selectedCount -gt 0) { "Green" } else { "Gray" }
        
        Write-Host "  Global Actions:" -ForegroundColor Cyan
        Write-Host "    [R] Run Selected Tasks (" -NoNewline -ForegroundColor White
        Write-Host $selectedText -NoNewline -ForegroundColor $selectedColor
        Write-Host ")" -ForegroundColor White
        Write-Host "    [C] Clear All Selections" -ForegroundColor White
        Write-Host "    [Q] Quit WinSuture" -ForegroundColor White
        Write-Host ""
        Write-Host "========================================================================================" -ForegroundColor Cyan
        
        if ($alertMessage) {
            Write-Host "  [*] $alertMessage" -ForegroundColor $alertColor
            Write-Host "========================================================================================" -ForegroundColor Cyan
            $alertMessage = ""
        }
        
        Write-Host "  Select a category screen [1, 2, 3] or a global action [R, C, Q]" -ForegroundColor DarkCyan
        $input = Read-Host "  WinSuture CLI"
        $input = $input.Trim().Replace("'", "").Replace('"', "").ToUpper()
        
        if ($input -eq "1" -or $input -eq "OPT") {
            $script:activeScreen = "O"
            $alertMessage = "Opened Optimizations screen."
            $alertColor = "Green"
        }
        elseif ($input -eq "2" -or $input -eq "REP") {
            $script:activeScreen = "R"
            $alertMessage = "Opened Repairs screen."
            $alertColor = "Green"
        }
        elseif ($input -eq "3" -or $input -eq "BKP") {
            $script:activeScreen = "B"
            $alertMessage = "Opened Backup & Restore screen."
            $alertColor = "Green"
        }
        elseif ($input -eq "Q") {
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
        elseif ($input -eq "R") {
            Invoke-RunSelected
        }
        else {
            $alertMessage = "Invalid option: '$input'"
            $alertColor = "Red"
        }
        continue
    }

    # Generate layout lines and subtitle for the active screen
    $lines = @()
    $subtitle = ""
    if ($script:activeScreen -eq "O") {
        $lines = Get-LayoutLines -items $opts
        $subtitle = "Presets: P1 (Basic Opts) | P2 (Advanced Opts) | C (Clear All) | M (Main Menu)"
    }
    elseif ($script:activeScreen -eq "R") {
        $lines = Get-LayoutLines -items $reps
        $subtitle = "Presets: P3 (System Repairs) | C (Clear All) | M (Main Menu)"
    }
    elseif ($script:activeScreen -eq "B") {
        $lines = Get-LayoutLines -items $backups
        $subtitle = "Consolidated Backups: B | C (Clear All) | M (Main Menu)"
    }
    
    # Render in a clean 2-column layout (split in half)
    $leftWidth = 46
    $half = [Math]::Ceiling($lines.Count / 2)
    for ($i = 0; $i -lt $half; $i++) {
        $left = $lines[$i]
        $right = if ($i + $half -lt $lines.Count) { $lines[$i + $half] } else { $null }
        
        # Format left column
        $leftText = ""
        $leftColor = "Gray"
        if ($null -ne $left) {
            if ($left.Type -eq "Header") {
                $leftText = " -- $($left.Text) --"
                $leftColor = "Cyan"
            }
            elseif ($left.Type -eq "Item") {
                $item = $left.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $leftText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $leftColor = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $leftColor = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $leftColor = "Red" }
            }
        }
        
        # Format right column
        $rightText = ""
        $rightColor = "Gray"
        if ($null -ne $right) {
            if ($right.Type -eq "Header") {
                $rightText = " -- $($right.Text) --"
                $rightColor = "Cyan"
            }
            elseif ($right.Type -eq "Item") {
                $item = $right.Item
                $selected = if ($item.Selected) { "[x]" } else { "[ ]" }
                $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                $rightText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                
                if ($item.Selected) { $rightColor = "Green" }
                elseif ($item.ScanStatus -eq "Recommended") { $rightColor = "Yellow" }
                elseif ($item.Danger -eq "Dangerous") { $rightColor = "Red" }
            }
        }
        
        # Render side-by-side
        Write-Host $leftText.PadRight($leftWidth) -NoNewline -ForegroundColor $leftColor
        Write-Host " | " -NoNewline -ForegroundColor Cyan
        Write-Host $rightText -ForegroundColor $rightColor
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
    Write-Host "  Inputs: <id,id,...> to toggle | OPT/REP/BKP to switch | M for Main Menu | S to Scan | R to Run | Q to Quit" -ForegroundColor DarkCyan
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
    elseif ($input -eq "OPT") {
        $script:activeScreen = "O"
        $alertMessage = "Switched to Optimizations screen."
        $alertColor = "Green"
    }
    elseif ($input -eq "REP") {
        $script:activeScreen = "R"
        $alertMessage = "Switched to Repairs screen."
        $alertColor = "Green"
    }
    elseif ($input -eq "BKP") {
        $script:activeScreen = "B"
        $alertMessage = "Switched to Backup & Restore screen."
        $alertColor = "Green"
    }
    elseif ($input -eq "M" -or $input -eq "MAIN") {
        $script:activeScreen = "M"
        $alertMessage = "Returned to Main Menu."
        $alertColor = "Green"
    }
    elseif ($input -eq "C") {
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            $tweaks[$i].Selected = $false
        }
        $alertMessage = "All selections cleared."
        $alertColor = "Yellow"
    }
    elseif ($input -eq "P1") {
        # Toggle Basic optimizations preset (only works/affects items on screen O)
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Category -eq "Optimization" -and $tweaks[$i].Packages -contains "Basic") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Basic Optimizations Preset (P1)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P2") {
        # Toggle Advanced optimizations preset (only works/affects items on screen O)
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Category -eq "Optimization" -and $tweaks[$i].Packages -contains "Advanced") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Advanced Optimizations Preset (P2)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P3") {
        # Toggle System Repairs preset (only works/affects items on screen R)
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Category -eq "Repair" -and $tweaks[$i].Packages -contains "Repairs") {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled System Repairs Preset (P3)."
        $alertColor = "Green"
    }
    elseif ($input -eq "B") {
        # Only allow consolidated backups from screen B
        if ($script:activeScreen -eq "B") {
            Draw-Header -subtitle "Running Consolidated Advanced Backups..."
            $global:WinSutureBackupDir = $null
            
            $backupItems = $tweaks | Where-Object { $_.Id -ge 43 -and $_.Id -le 46 }
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
        } else {
            $alertMessage = "Backups can only be run from the Backup & Restore screen (BKP)."
            $alertColor = "Red"
        }
    }
    elseif ($input -eq "S") {
        # Only allow scanning from optimizations and repairs
        if ($script:activeScreen -eq "O" -or $script:activeScreen -eq "R") {
            Write-Host "  [*] Initiating AeroDiagnostics scan for active category... Please wait..." -ForegroundColor Yellow
            $recCount = 0
            $recommendedIds = @()
            
            # Restrict scanning scope to active screen category
            $scanCategory = if ($script:activeScreen -eq "O") { "Optimization" } else { "Repair" }
            $scanItems = $tweaks | Where-Object { $_.Category -eq $scanCategory }
            
            foreach ($t in $scanItems) {
                $sb = Get-TweakScript -item $t
                if ($null -eq $sb) {
                    $t.ScanStatus = "Error"
                    continue
                }
                try {
                    $needsTweak = & $sb -Mode "Check"
                    if ($needsTweak) {
                        $t.ScanStatus = "Recommended"
                        $recommendedIds += $t.Id
                        $recCount++
                    } else {
                        $t.ScanStatus = "Healthy"
                    }
                } catch {
                    $t.ScanStatus = "Error"
                }
            }
            
            Write-Host "  [+] Scan complete! Found $recCount recommended improvements (marked with '*')." -ForegroundColor Yellow
            if ($recCount -gt 0) {
                $preselect = Read-Host "  Would you like to pre-select these $recCount recommendations? (Y/N)"
                if ($preselect.Trim().ToUpper() -eq "Y") {
                    foreach ($id in $recommendedIds) {
                        $item = $tweaks | Where-Object { $_.Id -eq $id }
                        if ($null -ne $item) {
                            $item.Selected = $true
                        }
                    }
                    $alertMessage = "Scan Complete! Recommended items have been pre-selected (marked with '*')."
                } else {
                    $alertMessage = "Scan Complete! Recommendations displayed (marked with '*'), but selection was not changed."
                }
            } else {
                $alertMessage = "Scan Complete! Your system is fully optimized according to the standard checks."
            }
            $alertColor = "Green"
        } else {
            $alertMessage = "Scanning is only supported on the Optimizations (OPT) and Repairs (REP) screens."
            $alertColor = "Red"
        }
    }
    elseif ($input -eq "R") {
        Invoke-RunSelected
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
                    $item = $tweaks | Where-Object { $_.Id -eq $cleanIdx }
                    if ($null -ne $item) {
                        # Validate that the item matches the active category
                        $isItemOnActiveScreen = $false
                        if ($script:activeScreen -eq "O" -and $item.Category -eq "Optimization") { $isItemOnActiveScreen = $true }
                        elseif ($script:activeScreen -eq "R" -and $item.Category -eq "Repair") { $isItemOnActiveScreen = $true }
                        elseif ($script:activeScreen -eq "B" -and $item.Category -eq "BackupRestore") { $isItemOnActiveScreen = $true }
                        
                        if ($isItemOnActiveScreen) {
                            $descItems += $item
                        }
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
                $alertMessage = "No valid active-screen item IDs found to describe."
                $alertColor = "Red"
            }
        }
        else {
            $successCount = 0
            foreach ($indexStr in $indices) {
                $cleanStr = $indexStr.Trim()
                if ($cleanStr -match '^\d+$') {
                    $cleanIdx = [int]$cleanStr
                    $item = $tweaks | Where-Object { $_.Id -eq $cleanIdx }
                    if ($null -ne $item) {
                        # Validate that the item matches the active category
                        $isItemOnActiveScreen = $false
                        if ($script:activeScreen -eq "O" -and $item.Category -eq "Optimization") { $isItemOnActiveScreen = $true }
                        elseif ($script:activeScreen -eq "R" -and $item.Category -eq "Repair") { $isItemOnActiveScreen = $true }
                        elseif ($script:activeScreen -eq "B" -and $item.Category -eq "BackupRestore") { $isItemOnActiveScreen = $true }
                        
                        if ($isItemOnActiveScreen) {
                            # Toggle selection
                            $item.Selected = -not $item.Selected
                            $successCount++
                        }
                    }
                }
            }
            
            if ($successCount -eq 0) {
                $alertMessage = "Invalid command or active-screen selection index: '$input'"
                $alertColor = "Red"
            } else {
                $alertMessage = "Toggled $successCount item(s)."
                $alertColor = "Green"
            }
        }
    }
}
