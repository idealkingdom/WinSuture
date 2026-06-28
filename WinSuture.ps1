# Force console output encoding to UTF-8 to display Unicode characters correctly
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Check for Administrator elevation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[-] Error: WinSuture must be run in an elevated PowerShell session!" -ForegroundColor Red
    Write-Host "[*] Please open PowerShell as Administrator and run the command again." -ForegroundColor Yellow
    Exit
}

# --- ENVIRONMENTAL SECURITY CHECKS ---
if ($ExecutionContext.SessionState.LanguageMode -eq "ConstrainedLanguage") {
    Write-Host "[-] WARNING: System is operating in Constrained Language Mode (WDAC/AppLocker)." -ForegroundColor Red
    Write-Host "[-] Many dynamic optimizations and compiling routines will be blocked." -ForegroundColor Red
    Write-Host "[-] Please run the compiled Offline payload if needed, or temporarily suspend policies." -ForegroundColor Yellow
}

# --- CONFIGURATION ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Hardcoded to specific immutable commit hash to prevent supply-chain tag mutations
$githubBaseUrl = "https://raw.githubusercontent.com/idealkingdom/WinSuture/c8b24d3d91d28b1e5c422ca3dcb49241acfe5459"
$global:WinSutureScriptRoot = $PSScriptRoot

# Helper to write persistent logs
function Write-WinSutureLog {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )
    $logDir = "$env:ProgramData\WinSuture\logs"
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logFile = Join-Path $logDir "winsuture_run.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logEntry -ErrorAction SilentlyContinue
}

# Safe Mode detection (SAFEBOOT environment variable is present in Safe Mode)
$isSafeMode = $null -ne [System.Environment]::GetEnvironmentVariable("SAFEBOOT")

# --- SYSTEM INFORMATION & VERSION CHECK ---
$osName = "Windows"
$osVersion = "Unknown"
$osBuild = 0
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($null -ne $os) {
        $osName = $os.Caption
        $osVersion = $os.Version
    } else {
        $os = Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($null -ne $os) {
            $osName = $os.Caption
            $osVersion = $os.Version
        }
    }
} catch {
    $osVersion = [System.Environment]::OSVersion.Version.ToString()
}

if ($osVersion -match '^\d+\.\d+\.(\d+)') {
    $osBuild = [int]$Matches[1]
} elseif ($osVersion -match '^(\d+)') {
    $osBuild = [int]$Matches[1]
}

# WinSuture is tested/supported up to Windows 10 Build 19045 (22H2) and Windows 11 Build 26200 (25H2)
$isFullyTested = $false
if ($osName -like "*Windows 10*") {
    if ($osBuild -le 19045) { $isFullyTested = $true }
} elseif ($osName -like "*Windows 11*") {
    if ($osBuild -le 26200) { $isFullyTested = $true }
}


# --- HELPER FUNCTIONS ---

# Helper to query system restore points compatibly across PowerShell 5.1 and 7.x
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

# Helper to load a tweak's unified scriptblock (sourcing from local relative directory or GitHub raw fallback)
function Get-TweakScript {
    param(
        [Parameter(Mandatory=$true)]
        $item
    )
    
    $code = $null
    
    # Check for local file path relative to the directory of this loader script
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $localPath = Join-Path $PSScriptRoot $item.Path
        if (Test-Path $localPath) {
            try {
                $code = Get-Content -Path $localPath -Raw -ErrorAction Stop
            } catch {
                Write-Warning "Failed to read local file '$localPath'. Attempting cloud fallback..."
            }
        }
    }
    
    # Fallback to downloading raw script from GitHub raw URL
    if ($null -eq $code) {
        $cloudUrl = "$githubBaseUrl/$($item.Path)"
        try {
            $response = Invoke-WebRequest -Uri $cloudUrl -UseBasicParsing -ErrorAction Stop
            $code = $response.Content
        } catch {
            Write-Error "Failed to load script block from local path or cloud URL: $cloudUrl"
            return $null
        }
    }

    # Validate Payload SHA-256 Hash
    if ($null -ne $item.Hash) {
        $normalizedCode = $code.Replace("`r`n", "`n")
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($normalizedCode)
        $hashObj = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
        $computedHash = [BitConverter]::ToString($hashObj).Replace("-", "").ToLower()
        if ($computedHash -ne $item.Hash) {
            Write-Host "[-] CRITICAL SECURITY ERROR: Payload hash mismatch for $($item.Path)!" -ForegroundColor Red
            Write-Host "[-] Expected: $($item.Hash)" -ForegroundColor Red
            Write-Host "[-] Computed: $computedHash" -ForegroundColor Red
            Write-Host "[-] Execution blocked to prevent potential malware execution." -ForegroundColor Red
            return $null
        }
    }

    return [scriptblock]::Create($code)
}

# Helper to load a manifest file with local path and fallback to cloud
function Load-ManifestFile {
    param(
        [string]$filename
    )
    $data = $null
    
    if (-not [string]::IsNullOrEmpty($PSScriptRoot)) {
        $localPath = Join-Path $PSScriptRoot $filename
        if (Test-Path $localPath) {
            try {
                $json = Get-Content -Path $localPath -Raw -ErrorAction Stop
                $data = ConvertFrom-Json $json
            } catch {
                Write-Warning "Failed to read local $filename. Attempting cloud download fallback..."
            }
        }
    }
    
    if ($null -eq $data) {
        $cloudUrl = "$githubBaseUrl/$filename"
        try {
            $response = Invoke-WebRequest -Uri $cloudUrl -UseBasicParsing -ErrorAction Stop
            $data = ConvertFrom-Json $response.Content
        } catch {
            Write-Host "[-] Critical Error: Failed to load manifest file '$filename' locally or from $cloudUrl" -ForegroundColor Red
            Write-Host "[-] Please check your internet connection or verify your `$githubBaseUrl path." -ForegroundColor Yellow
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
    $isSupported = $true
    if ($null -ne $t.SupportedOS) {
        $isSupported = $false
        foreach ($os in $t.SupportedOS) {
            if ($os -eq "All" -or $osName -like "*$os*") {
                $isSupported = $true
                break
            }
        }
    }
    $t | Add-Member -MemberType NoteProperty -Name "IsSupported" -Value $isSupported -Force

    # Backup tasks are no longer selected by default as they are chosen dynamically pre-run
    $defaultSelected = $false
    $t | Add-Member -MemberType NoteProperty -Name "Selected" -Value $defaultSelected -Force
    $t | Add-Member -MemberType NoteProperty -Name "ScanStatus" -Value "" -Force
    
    $reversible = $t.Category -eq "Optimization"
    $t | Add-Member -MemberType NoteProperty -Name "Reversible" -Value $reversible -Force
}

# Helper to clear the console screen and scrollback buffer robustly
function Clear-ConsoleScreen {
    try {
        [Console]::Clear()
    } catch {
        Clear-Host
    }
}

# Helper to structure items under their subcategory subheaders, partitioned into two columns
# such that no subcategory is split across columns.
function Get-PartitionedLayout {
    param(
        [array]$items
    )
    $leftLines = @()
    $rightLines = @()
    if ($null -eq $items -or $items.Count -eq 0) {
        return @{ Left = $leftLines; Right = $rightLines }
    }
    
    # Group items by subcategory
    $grouped = $items | Group-Object Subcategory
    
    # Find the mathematically optimal split index that minimizes the height difference
    # between the Left and Right columns while preserving sequential category order.
    $bestDiff = [int]::MaxValue
    $bestSplitIdx = 0
    
    for ($splitIdx = 0; $splitIdx -lt $grouped.Count; $splitIdx++) {
        $leftHeight = 0
        $rightHeight = 0
        
        for ($i = 0; $i -lt $grouped.Count; $i++) {
            $h = 1 + $grouped[$i].Count  # 1 for header, plus items count
            if ($i -le $splitIdx) {
                $leftHeight += $h
            } else {
                $rightHeight += $h
            }
        }
        
        $diff = [Math]::Abs($leftHeight - $rightHeight)
        if ($diff -lt $bestDiff) {
            $bestDiff = $diff
            $bestSplitIdx = $splitIdx
        }
    }
    
    # Build Left and Right layout lines arrays
    for ($i = 0; $i -lt $grouped.Count; $i++) {
        $g = $grouped[$i]
        $groupLines = @()
        $groupLines += [PSCustomObject]@{
            Type = "Header"
            Text = $g.Name
        }
        foreach ($item in $g.Group) {
            $groupLines += [PSCustomObject]@{
                Type = "Item"
                Item = $item
            }
        }
        
        if ($i -le $bestSplitIdx) {
            $leftLines += $groupLines
        } else {
            $rightLines += $groupLines
        }
    }
    
    return @{
        Left = $leftLines
        Right = $rightLines
    }
}

# Custom header renderer
function Draw-Header {
    param([string]$subtitle = "")
    Clear-ConsoleScreen
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host "                                WIN SUTURE POWER CLI TOOL                               " -ForegroundColor White
    Write-Host "========================================================================================" -ForegroundColor Cyan
    
    # Render Screen Tabs
    if ($script:activeScreen -ne "M") {
        $tabO = if ($script:activeScreen -eq "O") { "[*] OPTIMIZATIONS" } else { "    OPTIMIZATIONS" }
        $tabR = if ($script:activeScreen -eq "R") { "[*] REPAIRS      " } else { "    REPAIRS      " }
        $tabRS = if ($script:activeScreen -eq "RS") { "[*] RESTORES     " } else { "    RESTORES     " }
        
        $colorO = if ($script:activeScreen -eq "O") { "Green" } else { "Gray" }
        $colorR = if ($script:activeScreen -eq "R") { "Green" } else { "Gray" }
        $colorRS = if ($script:activeScreen -eq "RS") { "Green" } else { "Gray" }
        
        Write-Host "  " -NoNewline
        Write-Host $tabO -ForegroundColor $colorO -NoNewline
        Write-Host " | " -ForegroundColor Cyan -NoNewline
        Write-Host $tabR -ForegroundColor $colorR -NoNewline
        Write-Host " | " -ForegroundColor Cyan -NoNewline
        Write-Host $tabRS -ForegroundColor $colorRS
        
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
    param(
        [ValidateSet("Apply", "Disable")]
        [string]$Action = "Apply"
    )
    # Filter checked items (Restores are run separately via the interactive Restore Wizard)
    # 1. Filter optimizations and repairs selected by the user
    $tweakOrRepairItems = if ($Action -eq "Disable") {
        $tweaks | Where-Object { $_.Selected -eq $true -and $_.Reversible -eq $true -and $_.IsSupported -eq $true }
    } else {
        $tweaks | Where-Object { $_.Selected -eq $true -and $_.Category -ne "BackupRestore" -and $_.IsSupported -eq $true }
    }
    
    if ($tweakOrRepairItems.Count -eq 0) {
        if ($Action -eq "Disable") {
            $script:alertMessage = "No reversible items selected to revert. Please select reversible items first!"
        } else {
            $script:alertMessage = "No items selected to run. Please select items first!"
        }
        $script:alertColor = "Red"
        return
    }
    
    # Pre-run Backup Prompt Loop
    $selectedBackups = @{
        43 = $true  # Create Restore Point
        44 = $true  # Export Registry Hives
        45 = $true  # Backup hosts File
        46 = $true  # Backup Network Settings
    }
    
    $backupLoop = $true
    while ($backupLoop) {
        Draw-Header -subtitle "Pre-Run Backup Selection"
        Write-Host "  Before applying changes, select the backup components you want to run:" -ForegroundColor Cyan
        Write-Host ""
        
        $chk43 = if ($selectedBackups[43]) { "[x]" } else { "[ ]" }
        $chk44 = if ($selectedBackups[44]) { "[x]" } else { "[ ]" }
        $chk45 = if ($selectedBackups[45]) { "[x]" } else { "[ ]" }
        $chk46 = if ($selectedBackups[46]) { "[x]" } else { "[ ]" }
        
        Write-Host "    [1] $chk43 Create Restore Point       (Standard system checkpoint)" -ForegroundColor White
        Write-Host "    [2] $chk44 Export Registry Hives      (Saves HKCU and key HKLM hives)" -ForegroundColor White
        Write-Host "    [3] $chk45 Backup hosts File          (Saves network hosts configuration)" -ForegroundColor White
        Write-Host "    [4] $chk46 Backup Network Settings    (Logs current DNS and IP config)" -ForegroundColor White
        Write-Host ""
        Write-Host "========================================================================================" -ForegroundColor Cyan
        Write-Host "  Inputs: 1, 2, 3, 4 to toggle | R to Run Tasks | S to Skip Backups | C to Cancel Execution" -ForegroundColor DarkCyan
        
        $bInput = Read-Host "  Backup Selection"
        if ($null -eq $bInput) { continue }
        $bInput = $bInput.Trim().ToUpper()
        
        if ($bInput -eq "C" -or $bInput -eq "CANCEL") {
            $script:alertMessage = "Action execution aborted by user."
            $script:alertColor = "Yellow"
            return
        }
        elseif ($bInput -eq "S" -or $bInput -eq "SKIP") {
            foreach ($key in @($selectedBackups.Keys)) {
                $selectedBackups[$key] = $false
            }
            $backupLoop = $false
        }
        elseif ($bInput -eq "R" -or $bInput -eq "RUN") {
            $backupLoop = $false
        }
        elseif ($bInput -eq "1") { $selectedBackups[43] = -not $selectedBackups[43] }
        elseif ($bInput -eq "2") { $selectedBackups[44] = -not $selectedBackups[44] }
        elseif ($bInput -eq "3") { $selectedBackups[45] = -not $selectedBackups[45] }
        elseif ($bInput -eq "4") { $selectedBackups[46] = -not $selectedBackups[46] }
    }
    
    # Update selected status in main array
    $backupItems = $tweaks | Where-Object { $_.Id -ge 43 -and $_.Id -le 46 }
    foreach ($b in $backupItems) {
        $b.Selected = $selectedBackups[$b.Id]
    }
    
    # Final consolidated run list
    $selectedItems = if ($Action -eq "Disable") {
        $tweaks | Where-Object { ($_.Selected -eq $true -and $_.Reversible -eq $true -and $_.IsSupported -eq $true) -or ($_.Category -eq "BackupRestore" -and $_.Selected -eq $true) }
    } else {
        $tweaks | Where-Object { $_.Selected -eq $true -and $_.Subcategory -ne "System Restores" -and $_.IsSupported -eq $true }
    }
    
    # Check for dangerous items in the finalized run list
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
    
    # Create Restore Point before executing (only if selected)
    if ($selectedBackups[43]) {
        Write-Host "[*] Initiating pre-run safety checkpoints..." -ForegroundColor Yellow
        $checkpointSuccess = $false
        try {
            Checkpoint-Computer -Description "WinSutureRun" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
            Write-Host "[+] Pre-run Restore Point created successfully!" -ForegroundColor Green
            $checkpointSuccess = $true
        } catch {
            Write-Host "[-] Warning: Could not create Restore Point. System Protection may be disabled or rate-limited." -ForegroundColor Red
            Write-Host ""
            Write-Host "  Since system modifications are about to be applied, how would you like to proceed?" -ForegroundColor Cyan
            Write-Host "    [1] Attempt to Enable System Protection on Drive C: and retry" -ForegroundColor White
            Write-Host "    [2] Proceed anyway (WITHOUT a restore point)" -ForegroundColor Yellow
            Write-Host "    [3] Abort execution" -ForegroundColor Red
            Write-Host ""
            
            $choice = ""
            while ($choice -notin @("1", "2", "3")) {
                $choice = Read-Host "  Select an option (1, 2, or 3)"
                if ($null -ne $choice) { $choice = $choice.Trim() }
            }
            
            if ($choice -eq "1") {
                Write-Host "[*] Attempting to enable System Protection on Drive C:..." -ForegroundColor Yellow
                try {
                    Enable-ComputerRestore -Drive "C:\" -ErrorAction Stop
                    Write-Host "[+] System Protection enabled on Drive C:!" -ForegroundColor Green
                    Write-Host "[*] Retrying Restore Point creation..." -ForegroundColor Yellow
                    Checkpoint-Computer -Description "WinSutureRun" -RestorePointType "MODIFY_SETTINGS" -ErrorAction Stop | Out-Null
                    Write-Host "[+] Pre-run Restore Point created successfully!" -ForegroundColor Green
                    $checkpointSuccess = $true
                } catch {
                    Write-Host "[-] Failed to enable System Protection or create Restore Point: $_" -ForegroundColor Red
                    Write-Host "    Note: You may need to manually enable System Protection in System Properties (sysdm.cpl)." -ForegroundColor Yellow
                    $confirmProceed = Read-Host "  Proceed without a restore point anyway? (Y/N)"
                    if ($null -eq $confirmProceed -or $confirmProceed.Trim().ToUpper() -ne "Y") {
                        $script:alertMessage = "Action execution aborted by user due to missing restore point."
                        $script:alertColor = "Yellow"
                        return
                    }
                }
            }
            elseif ($choice -eq "3") {
                $script:alertMessage = "Action execution aborted by user."
                $script:alertColor = "Yellow"
                return
            }
        }
        Write-Host ""
    }
    
    # Sort selected items: Backups must run first! (excluding ID 43 since it was already run above)
    $sortedItems = @()
    $sortedItems += $selectedItems | Where-Object { $_.Category -eq "BackupRestore" -and $_.Subcategory -eq "System Backups" -and $_.Id -ne 43 }
    $sortedItems += $selectedItems | Where-Object { $_.Category -ne "BackupRestore" -or $_.Subcategory -ne "System Backups" }
    
    foreach ($item in $sortedItems) {
        $modeToRun = if ($item.Category -eq "BackupRestore") { "Apply" } else { $Action }
        Write-Host "[*] Executing Task $($item.Id): $($item.Name) ($modeToRun)..." -ForegroundColor Yellow
        Write-WinSutureLog "Executing Task $($item.Id): $($item.Name) ($modeToRun)" "INFO"
        
        $sb = Get-TweakScript -item $item
        if ($null -eq $sb) {
            Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
            Write-WinSutureLog "Task $($item.Id) FAILED: Could not load script block" "ERROR"
            continue
        }
        
        $ps = [PowerShell]::Create()
        $escapedRoot = if ($null -ne $global:WinSutureScriptRoot) { $global:WinSutureScriptRoot.Replace("'", "''") } else { "" }
        $escapedRestore = if ($null -ne $global:WinSutureRestoreFolder) { $global:WinSutureRestoreFolder.Replace("'", "''") } else { "" }
        # Initialize necessary global state and Undo Engine wrapper for the runspace
        $initCode = @"
            `$global:WinSutureScriptRoot = '$escapedRoot'
            `$global:WinSutureRestoreFolder = '$escapedRestore'
            
            function Write-WinSutureLog {
                param([string]`$Message, [string]`$Level = 'INFO')
                `$logDir = `"$env:ProgramData\WinSuture\logs`"
                `$logFile = Join-Path `$logDir `"winsuture_run.log`"
                `$timestamp = Get-Date -Format `"yyyy-MM-dd HH:mm:ss`"
                Add-Content -Path `$logFile -Value `"[`$timestamp] [`$Level] `$Message`" -ErrorAction SilentlyContinue
            }

            # State Store wrapper for Granular Undo Engine
            function Set-ItemProperty {
                param(
                    [Parameter(Mandatory=`$true, Position=0, ValueFromPipelineByPropertyName=`$true)] [string]`$Path,
                    [Parameter(Mandatory=`$true, Position=1)] [string]`$Name,
                    [Parameter(Mandatory=`$true, Position=2)] `$Value,
                    [Parameter()] [string]`$Type,
                    [Parameter()] [switch]`$Force
                )
                
                # 1. Capture original value
                `$oldValue = `$null
                try { `$oldValue = (Microsoft.PowerShell.Management\Get-ItemProperty -Path `$Path -Name `$Name -ErrorAction Stop).`$Name } catch {}
                
                # 2. Save state
                `$stateDir = `"$env:ProgramData\WinSuture\state`"
                if (-not (Test-Path `$stateDir)) { New-Item -ItemType Directory -Path `$stateDir -Force | Out-Null }
                `$stateFile = Join-Path `$stateDir "$($item.Id)_registry.json"
                
                `$stateObj = @{ Path=`$Path; Name=`$Name; OldValue=`$oldValue; NewValue=`$Value; Action='Set-ItemProperty' }
                `$stateObj | ConvertTo-Json -Compress -Depth 5 | Add-Content -Path `$stateFile
                
                # 3. Call real cmdlet
                if (`$PSBoundParameters.ContainsKey('Type')) {
                    Microsoft.PowerShell.Management\Set-ItemProperty -Path `$Path -Name `$Name -Value `$Value -Type `$Type -Force:`$Force -ErrorAction SilentlyContinue
                } else {
                    Microsoft.PowerShell.Management\Set-ItemProperty -Path `$Path -Name `$Name -Value `$Value -Force:`$Force -ErrorAction SilentlyContinue
                }
            }
"@
        $ps.AddScript($initCode).AddScript($sb.ToString()).AddParameter("Mode", $modeToRun) | Out-Null
        
        try {
            $asyncResult = $ps.BeginInvoke()
            $spinChars = @('|', '/', '-', '\')
            $spinIdx = 0
            while (-not $asyncResult.IsCompleted) {
                Write-Progress -Activity "Executing Task $($item.Id): $($item.Name)" -Status "Running... $($spinChars[$spinIdx])" -PercentComplete -1
                Start-Sleep -Milliseconds 100
                $spinIdx = ($spinIdx + 1) % 4
            }
            Write-Progress -Activity "Executing Task $($item.Id): $($item.Name)" -Completed
            
            $ps.EndInvoke($asyncResult) | Out-Null
            
            if ($ps.Streams.Error.Count -gt 0) {
                $err = $ps.Streams.Error[0].Exception.Message
                Write-Host "    [FAILED] Error: $err" -ForegroundColor Red
                Write-WinSutureLog "Task $($item.Id) FAILED: $err" "ERROR"
            } else {
                Write-Host "    [SUCCESS]" -ForegroundColor Green
                Write-WinSutureLog "Task $($item.Id) SUCCESS" "SUCCESS"
            }
        } catch {
            Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
            Write-WinSutureLog "Task $($item.Id) FAILED: $_" "ERROR"
        } finally {
            $ps.Dispose()
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

function Invoke-FolderRestoreSubmenu {
    param(
        [Parameter(Mandatory=$true)]
        $folder
    )
    
    $selectedReg = $true
    $selectedHosts = $true
    $selectedNet = $true
    
    $subAlertMessage = ""
    $subAlertColor = "Yellow"
    
    while ($true) {
        Draw-Header -subtitle "Restore Folder: $($folder.Name)"
        
        Write-Host "  Folder Path: $($folder.FullName)" -ForegroundColor Gray
        Write-Host ""
        Write-Host "  Select components to restore from this backup folder:" -ForegroundColor Cyan
        
        $chkReg = if ($selectedReg) { "[x]" } else { "[ ]" }
        $chkHosts = if ($selectedHosts) { "[x]" } else { "[ ]" }
        $chkNet = if ($selectedNet) { "[x]" } else { "[ ]" }
        
        Write-Host "    [1] $chkReg Registry Hives (Imports HKCU/SOFTWARE/SYSTEM hives)" -ForegroundColor White
        Write-Host "    [2] $chkHosts hosts File     (Replaces system hosts configuration)" -ForegroundColor White
        Write-Host "    [3] $chkNet Network Config  (Resets IP/Winsock catalog defaults)" -ForegroundColor White
        Write-Host ""
        Write-Host "========================================================================================" -ForegroundColor Cyan
        
        if ($subAlertMessage) {
            Write-Host "  [*] $subAlertMessage" -ForegroundColor $subAlertColor
            Write-Host "========================================================================================" -ForegroundColor Cyan
            $subAlertMessage = ""
        }
        
        Write-Host "  Inputs: 1, 2, or 3 to toggle selection | R to Run Restore | C to Cancel | HELP | Q to Quit" -ForegroundColor DarkCyan
        $subInput = Read-Host "  WinSuture Folder Restore"
        $subInput = $subInput.Trim().Replace("'", "").Replace('"', "").ToUpper()
        
        if ($subInput -eq "C" -or $subInput -eq "CANCEL") {
            $script:alertMessage = "Folder restore cancelled."
            $script:alertColor = "Yellow"
            break
        }
        elseif ($subInput -eq "Q") {
            Clear-Host
            Write-Host "[+] Thank you for using WinSuture! Goodbye." -ForegroundColor Green
            exit
        }
        elseif ($subInput -eq "SYS-REBOOT") {
            Write-Host "  [*] Rebooting computer in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit
        }
        elseif ($subInput -eq "SYS-REBOOT-SAFE") {
            Write-Host "  [*] Configuring system for Safe Mode and rebooting in 5 seconds..." -ForegroundColor Yellow
            bcdedit /set "{current}" safeboot minimal | Out-Null
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit
        }
        elseif ($subInput -eq "HELP") {
            Draw-Header -subtitle "WinSuture CLI Help"
            Write-Host "  Available Commands:" -ForegroundColor Yellow
            Write-Host "  <id>,<id>        : Toggle selection of items (e.g., 1, 3, 5)" -ForegroundColor White
            Write-Host "  <id> -D          : Display detailed description for an item (e.g., 1 -D)" -ForegroundColor White
            Write-Host "  OPT              : Switch to Optimizations screen" -ForegroundColor White
            Write-Host "  REP              : Switch to Repairs screen" -ForegroundColor White
            Write-Host "  RST              : Switch to System Restores screen" -ForegroundColor White
            Write-Host "  M / MAIN         : Return to Main Menu" -ForegroundColor White
            Write-Host "  S                : Scan active category for recommended tweaks/repairs" -ForegroundColor White
            Write-Host "  R                : Run all selected items" -ForegroundColor White
            Write-Host "  C                : Clear all selections" -ForegroundColor White
            Write-Host "  P1 / P2 / P3     : Toggle presets (Basic / Advanced / Repairs)" -ForegroundColor White
            Write-Host "  SYS-REBOOT       : Reboot the computer normally" -ForegroundColor White
            Write-Host "  SYS-REBOOT-SAFE  : Configure Safe Mode and reboot" -ForegroundColor White
            Write-Host "  HELP             : Show this help screen" -ForegroundColor White
            Write-Host "  Q                : Quit WinSuture" -ForegroundColor White
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Pause
            $subAlertMessage = "Help menu closed."
            $subAlertColor = "Yellow"
            continue
        }
        elseif ($subInput -eq "1") {
            $selectedReg = -not $selectedReg
            $subAlertMessage = "Toggled Registry Hives."
            $subAlertColor = "Green"
        }
        elseif ($subInput -eq "2") {
            $selectedHosts = -not $selectedHosts
            $subAlertMessage = "Toggled hosts File."
            $subAlertColor = "Green"
        }
        elseif ($subInput -eq "3") {
            $selectedNet = -not $selectedNet
            $subAlertMessage = "Toggled Network Config."
            $subAlertColor = "Green"
        }
        elseif ($subInput -eq "R" -or $subInput -eq "RUN") {
            if (-not $selectedReg -and -not $selectedHosts -and -not $selectedNet) {
                $subAlertMessage = "Please select at least one component to restore!"
                $subAlertColor = "Red"
                continue
            }
            
            Draw-Header -subtitle "Executing Selected Restores..."
            
            # Set the global restore folder variable that our scripts will check
            $global:WinSutureRestoreFolder = $folder.FullName
            
            # Execute Registry Restore (ID 48)
            if ($selectedReg) {
                $item = $tweaks | Where-Object { $_.Id -eq 48 }
                if ($null -ne $item) {
                    Write-Host "[*] Running Registry Restore..." -ForegroundColor Yellow
                    $sb = Get-TweakScript -item $item
                    if ($null -ne $sb) {
                        try {
                            & $sb -Mode "Apply"
                            Write-WinSutureLog "Registry Restore SUCCESS" "SUCCESS"
                        } catch {
                            Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
                            Write-WinSutureLog "Registry Restore FAILED: $_" "ERROR"
                        }
                    } else {
                        Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
                        Write-WinSutureLog "Registry Restore FAILED: Could not load script block" "ERROR"
                    }
                    Write-Host ""
                }
            }
            
            # Execute hosts File Restore (ID 49)
            if ($selectedHosts) {
                $item = $tweaks | Where-Object { $_.Id -eq 49 }
                if ($null -ne $item) {
                    Write-Host "[*] Running hosts File Restore..." -ForegroundColor Yellow
                    $sb = Get-TweakScript -item $item
                    if ($null -ne $sb) {
                        try {
                            & $sb -Mode "Apply"
                            Write-WinSutureLog "hosts File Restore SUCCESS" "SUCCESS"
                        } catch {
                            Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
                            Write-WinSutureLog "hosts File Restore FAILED: $_" "ERROR"
                        }
                    } else {
                        Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
                        Write-WinSutureLog "hosts File Restore FAILED: Could not load script block" "ERROR"
                    }
                    Write-Host ""
                }
            }
            
            # Execute Network Reset (ID 50)
            if ($selectedNet) {
                $item = $tweaks | Where-Object { $_.Id -eq 50 }
                if ($null -ne $item) {
                    Write-Host "[*] Running Network stack reset..." -ForegroundColor Yellow
                    $sb = Get-TweakScript -item $item
                    if ($null -ne $sb) {
                        try {
                            & $sb -Mode "Apply"
                            Write-WinSutureLog "Network Config Restore SUCCESS" "SUCCESS"
                        } catch {
                            Write-Host "    [FAILED] Error: $_" -ForegroundColor Red
                            Write-WinSutureLog "Network Config Restore FAILED: $_" "ERROR"
                        }
                    } else {
                        Write-Host "    [FAILED] Error: Could not load script block" -ForegroundColor Red
                        Write-WinSutureLog "Network Config Restore FAILED: Could not load script block" "ERROR"
                    }
                    Write-Host ""
                }
            }
            
            # Reset global restore folder variable
            $global:WinSutureRestoreFolder = $null
            
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Write-Host "  Selected restore operations completed!" -ForegroundColor Green
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Pause
            
            $script:alertMessage = "Selected restore operations completed."
            $script:alertColor = "Green"
            break
        }
        else {
            $subAlertMessage = "Invalid input: '$subInput'"
            $subAlertColor = "Red"
        }
    }
}

function Invoke-RestoreWizard {
    $wizardAlertMessage = $script:alertMessage
    $wizardAlertColor = $script:alertColor
    $script:alertMessage = "" # Clear global alert
    
    # 1. Detect restore points (wrapped in @() to force array casting for correct count evaluations)
    $restorePoints = @()
    try {
        $restorePoints = @(Get-RestorePointsSafe | Sort-Object SequenceNumber -Descending)
    } catch {}
    
    # 2. Detect script directory backup folders
    $baseDir = $PSScriptRoot
    if ($null -ne $global:WinSutureScriptRoot) {
        $baseDir = $global:WinSutureScriptRoot
    }
    if ($null -eq $baseDir -or $baseDir -eq "") {
        $baseDir = "$env:SystemDrive\WinSuture\Backups"
        if (-not (Test-Path $baseDir)) { New-Item -ItemType Directory -Path $baseDir -Force | Out-Null }
    }
    $backupDirs = @()
    try {
        $backupDirs = Get-ChildItem -Path $baseDir -Filter "WinSuture_Backup_*" -Directory -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
    } catch {}
    
    Draw-Header -subtitle "System Restore Wizard: Select a Restore Point or Backup Folder"
    
    # 3. Print System Restore Points
    Write-Host " [System Restore Points]" -ForegroundColor Cyan
    if ($restorePoints.Count -eq 0) {
        Write-Host "   [-] No Windows system restore points found (or protection is disabled)." -ForegroundColor Gray
    } else {
        for ($i = 0; $i -lt $restorePoints.Count; $i++) {
            $rp = $restorePoints[$i]
            Write-Host "   [R$($i+1)] Sequence #$($rp.SequenceNumber) - $($rp.Description) (Created: $($rp.CreationTime))" -ForegroundColor White
        }
    }
    Write-Host ""
    
    # 4. Print Local Backup Folders
    Write-Host " [Local Script Backup Folders]" -ForegroundColor Cyan
    if ($backupDirs.Count -eq 0) {
        Write-Host "   [-] No local WinSuture backup folders found in the script directory." -ForegroundColor Gray
    } else {
        for ($i = 0; $i -lt $backupDirs.Count; $i++) {
            $bd = $backupDirs[$i]
            Write-Host "   [F$($i+1)] $($bd.Name) (Created: $($bd.CreationTime))" -ForegroundColor White
        }
    }
    Write-Host ""
    Write-Host "========================================================================================" -ForegroundColor Cyan
    
    if ($wizardAlertMessage) {
        Write-Host "  [*] $wizardAlertMessage" -ForegroundColor $wizardAlertColor
        Write-Host "========================================================================================" -ForegroundColor Cyan
    }
    
    Write-Host "  Inputs: R1/R2... for Restore Point | F1/F2... for Local Backup | OPT/REP/RST to switch | M for Menu | HELP | Q to Quit" -ForegroundColor DarkCyan
    $wizInput = Read-Host "  WinSuture Restore Wizard"
    $wizInput = $wizInput.Trim().Replace("'", "").Replace('"', "").ToUpper()
    
    if ($wizInput -eq "Q") {
        Clear-Host
        Write-Host "[+] Thank you for using WinSuture! Goodbye." -ForegroundColor Green
        exit
    }
    elseif ($wizInput -eq "SYS-REBOOT") {
        Write-Host "  [*] Rebooting computer in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    }
    elseif ($wizInput -eq "SYS-REBOOT-SAFE") {
        Write-Host "  [*] Configuring system for Safe Mode and rebooting in 5 seconds..." -ForegroundColor Yellow
        bcdedit /set "{current}" safeboot minimal | Out-Null
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    }
    elseif ($wizInput -eq "HELP") {
        Draw-Header -subtitle "WinSuture CLI Help"
        Write-Host "  Available Commands:" -ForegroundColor Yellow
        Write-Host "  <id>,<id>        : Toggle selection of items (e.g., 1, 3, 5)" -ForegroundColor White
        Write-Host "  <id> -D          : Display detailed description for an item (e.g., 1 -D)" -ForegroundColor White
        Write-Host "  OPT              : Switch to Optimizations screen" -ForegroundColor White
        Write-Host "  REP              : Switch to Repairs screen" -ForegroundColor White
        Write-Host "  RST              : Switch to System Restores screen" -ForegroundColor White
        Write-Host "  M / MAIN         : Return to Main Menu" -ForegroundColor White
        Write-Host "  S                : Scan active category for recommended tweaks/repairs" -ForegroundColor White
        Write-Host "  R                : Run all selected items" -ForegroundColor White
        Write-Host "  C                : Clear all selections" -ForegroundColor White
        Write-Host "  P1 / P2 / P3     : Toggle presets (Basic / Advanced / Repairs)" -ForegroundColor White
        Write-Host "  SYS-REBOOT       : Reboot the computer normally" -ForegroundColor White
        Write-Host "  SYS-REBOOT-SAFE  : Configure Safe Mode and reboot" -ForegroundColor White
        Write-Host "  HELP             : Show this help screen" -ForegroundColor White
        Write-Host "  Q                : Quit WinSuture" -ForegroundColor White
        Write-Host "========================================================================================" -ForegroundColor Cyan
        Pause
        $script:alertMessage = "Help menu closed."
        $script:alertColor = "Yellow"
        return
    }
    elseif ($wizInput -eq "OPT") {
        $script:activeScreen = "O"
        $script:alertMessage = "Switched to Optimizations screen."
        $script:alertColor = "Green"
        return
    }
    elseif ($wizInput -eq "REP") {
        $script:activeScreen = "R"
        $script:alertMessage = "Switched to Repairs screen."
        $script:alertColor = "Green"
        return
    }
    elseif ($wizInput -eq "M" -or $wizInput -eq "MAIN") {
        $script:activeScreen = "M"
        $script:alertMessage = "Returned to Main Menu."
        $script:alertColor = "Green"
        return
    }
    elseif ($wizInput -match '^R\d+$') {
        # Restore Point rollback selected
        $idxStr = $wizInput.Substring(1)
        $idx = [int]$idxStr - 1
        if ($idx -lt 0 -or $idx -ge $restorePoints.Count) {
            $script:alertMessage = "Invalid Restore Point selection: '$wizInput'"
            $script:alertColor = "Red"
            return
        }
        
        $selectedRP = $restorePoints[$idx]
        Draw-Header -subtitle "System Restore Point Rollback Confirmation"
        Write-Host "[!] WARNING: You have selected Windows System Restore Point:" -ForegroundColor Red
        Write-Host "    Sequence #$($selectedRP.SequenceNumber) - $($selectedRP.Description) (Created: $($selectedRP.CreationTime))" -ForegroundColor White
        Write-Host ""
        Write-Host "    * System Restore will roll back system settings, drivers, and core OS state." -ForegroundColor Yellow
        Write-Host "    * Your computer WILL restart automatically to finalize this action." -ForegroundColor Yellow
        Write-Host "    * Make sure all work is saved before continuing." -ForegroundColor Yellow
        Write-Host ""
        $confirm = Read-Host "  Are you sure you want to rollback to this restore point? (Type 'CONFIRM_RESTORE')"
        if ($confirm.Trim() -eq "CONFIRM_RESTORE") {
            Draw-Header -subtitle "Restoring system state..."
            Write-Host "[*] Restoring system using Sequence Number $($selectedRP.SequenceNumber)..." -ForegroundColor Yellow
            try {
                Restore-Computer -RestorePoint $selectedRP.SequenceNumber -ErrorAction Stop
            } catch {
                Write-Host "[-] Programmatic restore failed: $_" -ForegroundColor Red
                Write-Host "[*] Attempting to launch native restore utility (rstrui.exe)..." -ForegroundColor Yellow
                try {
                    Start-Process "rstrui.exe"
                    Write-Host "[+] Opened rstrui.exe successfully." -ForegroundColor Green
                } catch {
                    Write-Host "[-] Failed to open rstrui.exe: $_" -ForegroundColor Red
                }
                Pause
            }
        } else {
            $script:alertMessage = "Restore rollback cancelled by user."
            $script:alertColor = "Yellow"
        }
        return
    }
    elseif ($wizInput -match '^F\d+$') {
        # Local Backup Folder selected
        $idxStr = $wizInput.Substring(1)
        $idx = [int]$idxStr - 1
        if ($idx -lt 0 -or $idx -ge $backupDirs.Count) {
            $script:alertMessage = "Invalid Backup Folder selection: '$wizInput'"
            $script:alertColor = "Red"
            return
        }
        
        $selectedFolder = $backupDirs[$idx]
        Invoke-FolderRestoreSubmenu -folder $selectedFolder
        return
    }
    else {
        $script:alertMessage = "Invalid command or selection: '$wizInput'"
        $script:alertColor = "Red"
        return
    }
}

# Main input loop
$alertMessage = ""
$alertColor = "Yellow"

while ($true) {
    # If on Main Menu, display it and continue loop
    if ($script:activeScreen -eq "M") {
        Draw-Header
        
        Write-Host "  System OS:  $osName (Build $osVersion)" -ForegroundColor White
        
        if (-not $isFullyTested) {
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Write-Host "                           !!! UNTESTED WINDOWS VERSION !!!                             " -ForegroundColor Red
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Write-Host "  WARNING: WinSuture is running on a newer/untested Windows build ($osVersion)." -ForegroundColor Yellow
            Write-Host "  System directories, registry layouts, and services may have changed." -ForegroundColor White
            Write-Host "  Applying tweaks or repairs on this version could lead to unexpected results." -ForegroundColor White
            Write-Host "  [!] RECOMMENDATION: Please run a full backup (Create Restore Point) before proceeding." -ForegroundColor Yellow
            Write-Host "========================================================================================" -ForegroundColor Cyan
        }
        
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
        Write-Host "    [3] System Restores (Interactive Restore Wizard)" -ForegroundColor White
        Write-Host ""
        
        # Calculate selected items count
        $selectedCount = ($tweaks | Where-Object { $_.Selected -eq $true }).Count
        $selectedText = if ($selectedCount -gt 0) { "$selectedCount items selected" } else { "none selected" }
        $selectedColor = if ($selectedCount -gt 0) { "Green" } else { "Gray" }
        
        $reversibleCount = ($tweaks | Where-Object { $_.Selected -eq $true -and $_.Reversible -eq $true }).Count
        $reversibleText = if ($reversibleCount -gt 0) { "$reversibleCount reversible items" } else { "none" }
        $reversibleColor = if ($reversibleCount -gt 0) { "Green" } else { "Gray" }
        
        Write-Host "  Global Actions:" -ForegroundColor Cyan
        Write-Host "    [R] Run/Apply Selected Tasks (" -NoNewline -ForegroundColor White
        Write-Host $selectedText -NoNewline -ForegroundColor $selectedColor
        Write-Host ")" -ForegroundColor White
        Write-Host "    [D] Revert/Disable Selected Tasks (" -NoNewline -ForegroundColor White
        Write-Host $reversibleText -NoNewline -ForegroundColor $reversibleColor
        Write-Host ")" -ForegroundColor White
        Write-Host "    [C] Clear All Selections" -ForegroundColor White
        Write-Host "    [HELP] Show all commands" -ForegroundColor White
        Write-Host "    [SYS-REBOOT] Reboot computer" -ForegroundColor White
        Write-Host "    [SYS-REBOOT-SAFE] Reboot in Safe Mode" -ForegroundColor White
        Write-Host "    [Q] Quit WinSuture" -ForegroundColor White
        Write-Host ""
        Write-Host "========================================================================================" -ForegroundColor Cyan
        
        if ($alertMessage) {
            Write-Host "  [*] $alertMessage" -ForegroundColor $alertColor
            Write-Host "========================================================================================" -ForegroundColor Cyan
            $alertMessage = ""
        }
        
        Write-Host "  Select a category screen [1, 2, 3] or a global action [R, D, C, HELP, SYS-REBOOT, Q]" -ForegroundColor DarkCyan
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
        elseif ($input -eq "3" -or $input -eq "RST") {
            $script:activeScreen = "RS"
            $alertMessage = "Opened System Restores screen."
            $alertColor = "Green"
        }
        elseif ($input -eq "Q") {
            Clear-ConsoleScreen
            Write-Host "[+] Thank you for using WinSuture! Goodbye." -ForegroundColor Green
            exit
        }
        elseif ($input -eq "SYS-REBOOT") {
            Write-Host "  [*] Rebooting computer in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit
        }
        elseif ($input -eq "SYS-REBOOT-SAFE") {
            Write-Host "  [*] Configuring system for Safe Mode and rebooting in 5 seconds..." -ForegroundColor Yellow
            bcdedit /set "{current}" safeboot minimal | Out-Null
            Start-Sleep -Seconds 5
            Restart-Computer -Force
            exit
        }
        elseif ($input -eq "HELP") {
            Draw-Header -subtitle "WinSuture CLI Help"
            Write-Host "  Available Commands:" -ForegroundColor Yellow
            Write-Host "  <id>,<id>        : Toggle selection of items (e.g., 1, 3, 5)" -ForegroundColor White
            Write-Host "  <id> -D          : Display detailed description for an item (e.g., 1 -D)" -ForegroundColor White
            Write-Host "  OPT              : Switch to Optimizations screen" -ForegroundColor White
            Write-Host "  REP              : Switch to Repairs screen" -ForegroundColor White
            Write-Host "  BKP              : Switch to System Backups screen" -ForegroundColor White
            Write-Host "  RST              : Switch to System Restores screen" -ForegroundColor White
            Write-Host "  M / MAIN         : Return to Main Menu" -ForegroundColor White
            Write-Host "  S                : Scan active category for recommended tweaks/repairs" -ForegroundColor White
            Write-Host "  R                : Run all selected items" -ForegroundColor White
            Write-Host "  D                : Revert/Disable all selected reversible items" -ForegroundColor White
            Write-Host "  C                : Clear all selections" -ForegroundColor White
            Write-Host "  P1 / P2 / P3     : Toggle presets (Basic / Advanced / Repairs)" -ForegroundColor White
            Write-Host "  B                : Run Consolidated Advanced Backups (from BKP screen)" -ForegroundColor White
            Write-Host "  SYS-REBOOT       : Reboot the computer normally" -ForegroundColor White
            Write-Host "  SYS-REBOOT-SAFE  : Configure Safe Mode and reboot" -ForegroundColor White
            Write-Host "  HELP             : Show this help screen" -ForegroundColor White
            Write-Host "  Q                : Quit WinSuture" -ForegroundColor White
            Write-Host "========================================================================================" -ForegroundColor Cyan
            Pause
            $alertMessage = "Help menu closed."
            $alertColor = "Yellow"
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
        elseif ($input -eq "D") {
            Invoke-RunSelected -Action "Disable"
        }
        else {
            $alertMessage = "Invalid option: '$input'"
            $alertColor = "Red"
        }
        continue
    }

    # Generate partitioned layout lines and subtitle for the active screen
    if ($script:activeScreen -eq "RS") {
        Invoke-RestoreWizard
        continue
    }
    
    $partitioned = $null
    $subtitle = ""
    if ($script:activeScreen -eq "O") {
        $partitioned = Get-PartitionedLayout -items $opts
        $subtitle = "Presets: P1 (Basic Opts) | P2 (Advanced Opts) | C (Clear All) | M (Main Menu)"
    }
    elseif ($script:activeScreen -eq "R") {
        $partitioned = Get-PartitionedLayout -items $reps
        $subtitle = "Presets: P3 (System Repairs) | C (Clear All) | M (Main Menu)"
    }
    
    Draw-Header -subtitle $subtitle
    
    # Render in a clean 2-column layout (group-preserving partition)
    $leftWidth = 46
    $leftLines = if ($null -ne $partitioned) { $partitioned.Left } else { @() }
    $rightLines = if ($null -ne $partitioned) { $partitioned.Right } else { @() }
    $maxRows = [Math]::Max($leftLines.Count, $rightLines.Count)
    
    for ($i = 0; $i -lt $maxRows; $i++) {
        $left = if ($i -lt $leftLines.Count) { $leftLines[$i] } else { $null }
        $right = if ($i -lt $rightLines.Count) { $rightLines[$i] } else { $null }
        
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
                if (-not $item.IsSupported) {
                    $scanSym = "U"
                    $dangerSym = " "
                    $leftText = "{0}{1} {2}{3,2}. {4}" -f "[ ]", $scanSym, $dangerSym, $item.Id, $item.Name
                    $leftColor = "DarkGray"
                } else {
                    $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                    $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                    $leftText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                    
                    if ($item.Selected) { $leftColor = "Green" }
                    elseif ($item.ScanStatus -eq "Recommended") { $leftColor = "Yellow" }
                    elseif ($item.Danger -eq "Dangerous") { $leftColor = "Red" }
                }
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
                if (-not $item.IsSupported) {
                    $scanSym = "U"
                    $dangerSym = " "
                    $rightText = "{0}{1} {2}{3,2}. {4}" -f "[ ]", $scanSym, $dangerSym, $item.Id, $item.Name
                    $rightColor = "DarkGray"
                } else {
                    $scanSym = if ($item.ScanStatus -eq "Healthy") { "v" } elseif ($item.ScanStatus -eq "Recommended") { "*" } elseif ($item.ScanStatus -eq "Error") { "?" } else { " " }
                    $dangerSym = if ($item.Danger -eq "Dangerous") { "!" } else { " " }
                    $rightText = "{0}{1} {2}{3,2}. {4}" -f $selected, $scanSym, $dangerSym, $item.Id, $item.Name
                    
                    if ($item.Selected) { $rightColor = "Green" }
                    elseif ($item.ScanStatus -eq "Recommended") { $rightColor = "Yellow" }
                    elseif ($item.Danger -eq "Dangerous") { $rightColor = "Red" }
                }
            }
        }
        
        # Render side-by-side
        Write-Host $leftText.PadRight($leftWidth) -NoNewline -ForegroundColor $leftColor
        Write-Host " | " -NoNewline -ForegroundColor Cyan
        Write-Host $rightText -ForegroundColor $rightColor
    }
    
    Write-Host "========================================================================================" -ForegroundColor Cyan
    Write-Host "  Legend: [x] Checked | v Scanned Healthy | * Scanned Recommended | U Unsupported | ! Dangerous (Red)" -ForegroundColor DarkGray
    Write-Host "========================================================================================" -ForegroundColor Cyan
    
    if ($alertMessage) {
        Write-Host "  [*] $alertMessage" -ForegroundColor $alertColor
        Write-Host "========================================================================================" -ForegroundColor Cyan
        $alertMessage = ""
    }
    
    Write-Host "  Inputs: <id,id,...> to toggle | OPT/REP/RST to switch | M for Main Menu | S to Scan | R to Run | D to Revert | HELP | Q to Quit" -ForegroundColor DarkCyan
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
    elseif ($input -eq "SYS-REBOOT") {
        Write-Host "  [*] Rebooting computer in 5 seconds..." -ForegroundColor Yellow
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    }
    elseif ($input -eq "SYS-REBOOT-SAFE") {
        Write-Host "  [*] Configuring system for Safe Mode and rebooting in 5 seconds..." -ForegroundColor Yellow
        bcdedit /set "{current}" safeboot minimal | Out-Null
        Start-Sleep -Seconds 5
        Restart-Computer -Force
        exit
    }
    elseif ($input -eq "HELP") {
        Draw-Header -subtitle "WinSuture CLI Help"
        Write-Host "  Available Commands:" -ForegroundColor Yellow
        Write-Host "  <id>,<id>        : Toggle selection of items (e.g., 1, 3, 5)" -ForegroundColor White
        Write-Host "  <id> -D          : Display detailed description for an item (e.g., 1 -D)" -ForegroundColor White
        Write-Host "  OPT              : Switch to Optimizations screen" -ForegroundColor White
        Write-Host "  REP              : Switch to Repairs screen" -ForegroundColor White
        Write-Host "  RST              : Switch to System Restores screen" -ForegroundColor White
        Write-Host "  M / MAIN         : Return to Main Menu" -ForegroundColor White
        Write-Host "  S                : Scan active category for recommended tweaks/repairs" -ForegroundColor White
        Write-Host "  R                : Run all selected items" -ForegroundColor White
        Write-Host "  D                : Revert/Disable all selected reversible items" -ForegroundColor White
        Write-Host "  C                : Clear all selections" -ForegroundColor White
        Write-Host "  P1 / P2 / P3     : Toggle presets (Basic / Advanced / Repairs)" -ForegroundColor White
        Write-Host "  SYS-REBOOT       : Reboot the computer normally" -ForegroundColor White
        Write-Host "  SYS-REBOOT-SAFE  : Configure Safe Mode and reboot" -ForegroundColor White
        Write-Host "  HELP             : Show this help screen" -ForegroundColor White
        Write-Host "  Q                : Quit WinSuture" -ForegroundColor White
        Write-Host "========================================================================================" -ForegroundColor Cyan
        Pause
        $alertMessage = "Help menu closed."
        $alertColor = "Yellow"
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
    elseif ($input -eq "RST") {
        $script:activeScreen = "RS"
        $alertMessage = "Switched to System Restores screen."
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
            if ($tweaks[$i].Category -eq "Optimization" -and $tweaks[$i].Packages -contains "Basic" -and $tweaks[$i].IsSupported) {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Basic Optimizations Preset (P1)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P2") {
        # Toggle Advanced optimizations preset (only works/affects items on screen O)
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Category -eq "Optimization" -and $tweaks[$i].Packages -contains "Advanced" -and $tweaks[$i].IsSupported) {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled Advanced Optimizations Preset (P2)."
        $alertColor = "Green"
    }
    elseif ($input -eq "P3") {
        # Toggle System Repairs preset (only works/affects items on screen R)
        for ($i = 0; $i -lt $tweaks.Count; $i++) {
            if ($tweaks[$i].Category -eq "Repair" -and $tweaks[$i].Packages -contains "Repairs" -and $tweaks[$i].IsSupported) {
                $tweaks[$i].Selected = -not $tweaks[$i].Selected
            }
        }
        $alertMessage = "Toggled System Repairs Preset (P3)."
        $alertColor = "Green"
    }

    elseif ($input -eq "S") {
        # Only allow scanning from optimizations and repairs
        if ($script:activeScreen -eq "O" -or $script:activeScreen -eq "R") {
            Draw-Header -subtitle "Running AeroDiagnostics Scan..."
            Write-Host "  [*] Initiating AeroDiagnostics scan for active category... Please wait..." -ForegroundColor Yellow
            $recCount = 0
            $recommendedIds = @()
            
            # Restrict scanning scope to active screen category
            $scanCategory = if ($script:activeScreen -eq "O") { "Optimization" } else { "Repair" }
            $scanItems = $tweaks | Where-Object { $_.Category -eq $scanCategory }
            
            foreach ($t in $scanItems) {
                if (-not $t.IsSupported) {
                    $t.ScanStatus = "Unsupported"
                    continue
                }
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
                Write-Host "========================================================================================" -ForegroundColor Cyan
                Write-Host "  Scan Complete! Your system is fully optimized according to the standard checks." -ForegroundColor Green
                Write-Host "========================================================================================" -ForegroundColor Cyan
                Pause
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
    elseif ($input -eq "D") {
        Invoke-RunSelected -Action "Disable"
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
                        
                        if ($isItemOnActiveScreen) {
                            if (-not $item.IsSupported) {
                                $alertMessage = "Item $($item.Id) is not supported on this OS version."
                                $alertColor = "Yellow"
                            } else {
                                # Toggle selection
                                $item.Selected = -not $item.Selected
                                $successCount++
                            }
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
