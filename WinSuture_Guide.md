# WinSuture Power User Tweaking & Repair Guide

Welcome to the **WinSuture Guide**. This document contains the details for the **Top 20 Performance Optimizations & Enhancements** and the **Top 20 System Fixes & Repairs** for Windows 10 and Windows 11.

> [!WARNING]
> Modifying the registry and system configuration files can cause system instability if done incorrectly. Always run **Option B (Advanced Backup Suite)** before applying any tweaks.

> [!IMPORTANT]
> **Safe Mode Recommendation:** It is highly recommended to run WinSuture in **Safe Mode (Minimal or Network)**. This prevents active processes, locks on system hives, and third-party antivirus engines from interfering with registry modifications and troubleshooting repairs.

---

## 🛠️ Table of Contents
1. [🛡️ Safety & Advanced Backups Suite](#-safety--advanced-backups-suite)
2. [🚀 Top 20 Performance Optimizations & Enhancements](#-top-20-performance-optimizations--enhancements)
3. [🔧 Top 20 Windows Fixes & Repairs](#-top-20-windows-fixes--repairs)
4. [🎮 Interactive Suture Tool (WinSuture.ps1)](#-interactive-suture-tool-winsutureps1)

---

## 🛡️ Safety & Advanced Backups Suite

Instead of manual configuration, you can enter **`B`** in the WinSuture CLI. The script will automatically execute the **Advanced Backups Suite**:
1. **System Restore Point**: Calls PowerShell checkpoint commands to create a Windows rollback point.
2. **Registry Hive Backup**: Automatically exports `HKCU` (Current User), `HKLM\SOFTWARE` (Machine Software policies), and `HKLM\SYSTEM` (Machine Kernel drivers) to `.reg` file hives on your Desktop inside a timestamped folder.
3. **hosts File Backup**: Backs up the local hosts routing lookup file to `hosts.bak`.
4. **Network Settings Backup**: Logs active DNS server configurations and IP configurations to text diagnostic logs.

---

## 🚀 Top 20 Performance Optimizations & Enhancements

Below is the curated list of optimizations. Each action corresponds to a split script in the `/Optimizations/` subfolder.

### 1. Revert to Windows 10 Classic Context Menu
Removes the secondary "Show more options" layer in Windows 11's right-click context menu.
* **Path**: `Optimizations/1_ClassicContextMenu.ps1`
* **Registry Path:** `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32`
* **Restart Required**: Explorer shell restarts automatically.

### 2. Disable Bing Search in Start Menu
Prevents local search queries in the Start Menu from displaying online web suggestions.
* **Path**: `Optimizations/2_DisableBingSearch.ps1`
* **Registry Path:** `HKCU\Software\Policies\Microsoft\Windows\Explorer`

### 3. Decrease Menu Show Delay
Speeds up the response time of cascading submenus and UI hover elements.
* **Path**: `Optimizations/3_DecreaseMenuDelay.ps1`
* **Registry Path:** `HKCU\Control Panel\Desktop` -> `MenuShowDelay` = `20`

### 4. Disable NTFS Last Access Update
Stops writing a time-stamp update to a file's metadata every time it is read, saving disk write overhead.
* **Path**: `Optimizations/4_DisableNTFSLastAccess.ps1`
* **Registry Path:** `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem` -> `NtfsDisableLastAccessUpdate` = `1`

### 5. Enable Hardware-Accelerated GPU Scheduling (HAGS)
Delegates GPU memory scheduling directly to the graphics processor. (Required for NVIDIA DLSS 3 Frame Generation).
* **Path**: `Optimizations/5_EnableHAGS.ps1`
* **Registry Path:** `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers` -> `HwSchMode` = `2`
* **Restart Required**: PC Reboot.

### 6. Enable the Ultimate Performance Power Plan
Exposes the hidden Ultimate Performance power profile.
* **Path**: `Optimizations/6_UltimatePowerPlan.ps1`
* **Command**: `powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61`

### 7. Disable Virtualization-Based Security (VBS) & Memory Integrity (HVCI)
Stops hypervisor-based isolated execution blocks, releasing CPU overhead for higher game FPS.
* **Path**: `Optimizations/7_DisableVBS.ps1`
* **Danger**: **High Risk** (Reduces system core virtualization isolation).
* **Restart Required**: PC Reboot.

### 8. Disable Game DVR & Background Recording
Stops Windows from constantly recording your screen in the background.
* **Path**: `Optimizations/8_DisableGameDVR.ps1`

### 9. Remove Windows Startup Application Delay
Prevents Windows from delaying startup applications by 10 seconds during boot.
* **Path**: `Optimizations/9_DisableStartupDelay.ps1`

### 10. Disable Windows Telemetry & Diagnostics (DiagTrack)
Disables Microsoft's background diagnostic monitoring service.
* **Path**: `Optimizations/10_DisableTelemetry.ps1`

### 11. Disable Hibernation
Deletes the large `hiberfil.sys` file from your C: drive, reclaiming disk space.
* **Path**: `Optimizations/11_DisableHibernation.ps1`

### 12. Optimize Gaming Scheduling
Alters the priority scheduler so the CPU dedicates maximum slices to your active foreground game/app.
* **Path**: `Optimizations/12_OptimizeGamingScheduling.ps1`

### 13. Enable Large System Cache
Optimizes kernel memory allocation for system file caches (ideal for heavy read/writes).
* **Path**: `Optimizations/13_EnableLargeSystemCache.ps1`

### 14. Disable Windows Search Indexer (For SSD Users)
Disables background file index database compiling.
* **Path**: `Optimizations/14_DisableSearchIndexer.ps1`

### 15. Hide Widgets and Chat Icons
Removes the background WebView2 taskbar widgets from loading.
* **Path**: `Optimizations/15_HideTaskbarWidgets.ps1`
* **Restart Required**: Explorer shell restarts automatically.

### 16. Disable Tips, Ads, and Suggested Apps
Stops Windows recommendations and silent sponsored app installations in the background.
* **Path**: `Optimizations/16_DisableTipsAndAds.ps1`

### 17. Configure Storage Sense to Clean Temp Files Automatically
Purges temporary folders and cache directories on a regular schedule.
* **Path**: `Optimizations/17_StorageSenseAutoCleanup.ps1`

### 18. Disable HPET (High Precision Event Timer)
Disables platform event timer clock tracking to resolve stutter/latency in games.
* **Path**: `Optimizations/18_DisableHPETTimer.ps1`
* **Restart Required**: PC Reboot.

### 19. Optimize Network Latency (Disable Nagle's Algorithm)
Forces immediate packet dispatch in TCP stacks (drops ping in multiplayer games).
* **Path**: `Optimizations/19_OptimizeNetworkLatency.ps1`

### 20. Enable Message Signaled Interrupts (MSI Mode) on GPU
Forces the graphics card to utilize thread-safe message interrupts instead of legacy interrupt sharing.
* **Path**: `Optimizations/20_EnableGPUMSIMode.ps1`
* **Restart Required**: PC Reboot.

---

## 🔧 Top 20 Windows Fixes & Repairs

Each repair script is mapped to a split file in the `/Repairs/` subfolder.

### 21. Reset Windows Update Cache
Stops updating services and purges the `SoftwareDistribution` and `catroot2` databases.
* **Path**: `Repairs/21_ResetWindowsUpdateCache.ps1`

### 22. Reset Network Stack / IP
Flushes and resets TCP/IP stack parameters and Winsock catalog sockets configuration.
* **Path**: `Repairs/22_ResetNetworkStack.ps1`
* **Restart Required**: PC Reboot.

### 23. Run SFC Scan
Detects and repairs corrupted operating system files.
* **Path**: `Repairs/23_RunSFCScan.ps1`

### 24. Run DISM Restore Health
Connects to Windows Update to download and replace corrupted core operating system components.
* **Path**: `Repairs/24_RunDISMRepair.ps1`

### 25. Component Store Cleanup (StartComponentCleanup)
Purges old, superseded component files from the WinSxS directory.
* **Path**: `Repairs/25_ComponentStoreCleanup.ps1`

### 26. Reset Windows Store (WSReset)
Clears temporary Microsoft Store cache folders, fixing pending download hangs.
* **Path**: `Repairs/26_ResetWindowsStore.ps1`

### 27. Re-register All Default Windows / UWP Apps
Re-registers built-in default apps (Photos, Calculator, Settings) if they crash.
* **Path**: `Repairs/27_ReregisterUWPApps.ps1`

### 28. Repair and Rebuild the WMI Repository
Rebuilds the Windows Management Instrumentation repository database.
* **Path**: `Repairs/28_RebuildWMIRepository.ps1`
* **Danger**: **High Risk** (Can temporarily break third-party logging engines).

### 29. Re-register Volume Shadow Copy Service (VSS) DLLs
Re-registers backup vss engine DLLs to fix restore point failures.
* **Path**: `Repairs/29_ReregisterVSSDLLs.ps1`

### 30. Reset Windows Defender / Firewall Settings
Restores Firewall defaults, clearing blocking rule bugs created by third-party software.
* **Path**: `Repairs/30_ResetFirewallSettings.ps1`

### 31. Reset Local Group Policies to Defaults
Removes all group policies, correcting registry restrictions or disabled settings.
* **Path**: `Repairs/31_ResetLocalGroupPolicies.ps1`

### 32. Flush DNS Cache
Purges DNS cache indexes, resolving host resolution issues.
* **Path**: `Repairs/32_FlushRegisterDNS.ps1`

### 33. Purge and Restart Print Spooler
Stops spooler and deletes queued jobs to fix printing print loops.
* **Path**: `Repairs/33_ClearPrintSpoolerQueue.ps1`

### 34. Restore Default LNK File Associations
Resets `.lnk` shortcut file handlers, resolving launching bugs.
* **Path**: `Repairs/34_FixLNKFileAssociations.ps1`

### 35. Rebuild Windows Search Index
Purges and rebuilds index databases to repair Search bar hangs.
* **Path**: `Repairs/35_RebuildSearchIndex.ps1`

### 36. Repair Windows Installer Service (MSI)
Re-registers MSIEXEC packages in registry to fix install errors.
* **Path**: `Repairs/36_RepairMSIEngine.ps1`

### 37. Restore Default hosts File
Replaces modified hosts files with a clean default template.
* **Path**: `Repairs/37_RestoreDefaulthosts.ps1`

### 38. Restore Essential Windows Services Default Registry Startup Values
Enables core background system services that may have been disabled.
* **Path**: `Repairs/38_DefaultServicesStartup.ps1`

### 39. Clear Shell Icon Cache
Purges corrupted icon database cache, reloading Desktop task symbols.
* **Path**: `Repairs/39_ClearShellIconCache.ps1`
* **Restart Required**: Explorer shell restarts automatically.

### 40. Rebuild Boot Configuration Data (BCD)
Rebuilds boot records and parameters index database.
* **Path**: `Repairs/40_RebuildBCD.ps1`
* **Danger**: **High Risk** (Only run in recovery environment command line).
* **Restart Required**: PC Reboot.

### 41. Reset File Permissions
Resets default Windows system folder access control list permissions (via secedit configuration).
* **Path**: `Repairs/41_ResetFilePermissions.ps1`

### 42. Reset Registry Permissions
Resets core HKLM and HKCU registry key permissions back to standard default templates (via secedit configuration).
* **Path**: `Repairs/42_ResetRegistryPermissions.ps1`

---

## 🛡️ Backup & Restore Utilities

Each action is mapped to a split script in the `/BackupRestore/` subfolder.

### 43. Create Restore Point
Creates a new Windows System Restore Point checkpoint for system rollback.
* **Path**: `BackupRestore/43_CreateRestorePoint.ps1`

### 44. Export Registry Hives
Exports current user (HKCU) and local machine (SOFTWARE/SYSTEM) hives to .reg files on the Desktop.
* **Path**: `BackupRestore/44_BackupRegistryHives.ps1`

### 45. Backup hosts File
Copies the local system hosts lookup file to a backup hosts.bak file on the Desktop.
* **Path**: `BackupRestore/45_BackupHostsFile.ps1`

### 46. Backup Network Settings
Logs all active IP addresses, adapters, DNS client addresses, and routing tables to diagnostic reports on the Desktop.
* **Path**: `BackupRestore/46_BackupNetworkConfig.ps1`

### 47. Restore System Restore Point
Launches the native Windows System Restore interface wizard (`rstrui.exe`).
* **Path**: `BackupRestore/47_RestoreSystemRestorePoint.ps1`
* **Restart Required**: PC Reboot.

### 48. Restore Registry Hives
Prompts for a desktop backup folder path and imports the HKCU, SOFTWARE, or SYSTEM registry hive files back to the registry.
* **Path**: `BackupRestore/48_RestoreRegistryHives.ps1`
* **Danger**: **High Risk** (Modifies core registry configurations).
* **Restart Required**: PC Reboot.

### 49. Restore hosts File
Restores the backup hosts file template to replace the system hosts configuration.
* **Path**: `BackupRestore/49_RestoreHostsFile.ps1`

### 50. Restore Network Settings
Resets Winsock sockets, clears IP parameters, and flushes DNS client server definitions to restore network defaults.
* **Path**: `BackupRestore/50_RestoreNetworkConfig.ps1`
* **Restart Required**: PC Reboot.

---

## 🎮 Interactive Suture Tool (WinSuture.ps1)

A companion script `WinSuture.ps1` runs this entire checklist in an interactive command-line dashboard.

### Manifest Configuration
The database manifests are divided into three category-specific files:
* `optimizations.json` for performance adjustments
* `repairs.json` for troubleshooting and system repairs
* `backuprestore.json` for system backup and restoration

All items in the interactive checklist are grouped under subcategory subheaders (e.g. Gaming, Networking) for easy identification.

### How to Launch
Open **PowerShell as Administrator** and execute:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
& "d:\PG\WinEnhancer\WinSuture.ps1"
```

### CLI Menu Controls
* **Multi-Selection**: Toggle items on or off by typing their ID numbers separated by commas (e.g., `1,2,5,22,43`).
* **Item Description Help (`-d`)**: Appending `-d` after a comma-separated ID list will display the detailed description, category, and danger rating of those specific items (e.g., `1,2 -d` or `7,48 -d`).
* **Package Presets**: Group select settings based on predefined profiles:
  * Enter `P1` to toggle **Basic Optimizations** (safe UI & background adjustments).
  * Enter `P2` to toggle **Advanced Optimizations** (high-performance gaming & latency configurations).
  * Enter `P3` to toggle **System Repairs & Troubleshooting** (Winsock, SFC, DISM, DNS resets).
* **Advanced Backups Suite (`B`)**: Automatically runs and consolidates the four backup scripts (`43` to `46`), grouping all exported files into a single timestamped directory on your Desktop.
* **Scan System (`S`)**: Initiates the **"AeroDiagnostics & Performance Vulnerability Scan"**. This queries the active system registry and services to identify unoptimized configurations, then recommends which improvements to select.
* **Clear Selections (`C`)**: Cleans the checkmarks off all items.
* **Run Selected (`R`)**: Safely executes all checked actions. If any selected items are marked as high-risk, a security confirmation prompt will appear.
* **Quit (`Q`)**: Exits the utility.
