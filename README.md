# 🛡️ WinSuture

WinSuture is a modular, parameters-driven interactive CLI suite built for Windows 10 and 11 power users. It offers a single dashboard containing **20 advanced performance optimizations**, **22 critical system repairs**, and **8 automated backup/restore utilities**.

The entire tool is designed to run locally (fully offline) if the subfolders are present in the workspace, or fall back to dynamically streaming component script blocks directly from GitHub endpoints if running standalone.

---

## ⚡ Key Highlights
* **Main Menu Landing Screen**: A unified startup dashboard that integrates admin checks, system details, and the Safe Mode recommendation warning directly on launch.
* **Category Screens**: Dedicated visual screens for **Optimizations** (`OPT`), **Repairs** (`REP`), and **Backup & Restore** (`BKP`) to prevent terminal clutter and ensure no items scroll off the viewport.
* **Dual-Column Layout**: Items within each category screen are grouped cleanly under descriptive subheaders (e.g., `Gaming`, `Networking`, `System UI`) and formatted side-by-side.
* **Precedence Safety**: Backup tasks (creating restore points, registry exports, hosts backups) are prioritized and execute *first* before any system modifications are run.
* **Safe Mode Status**: Detects if the system is running in Windows Normal Mode versus Safe Mode and dynamically displays warning contexts directly on the Main Menu landing page.
* **Compatibility**: All Write-Host formatting parameter conflicts have been resolved to support Windows PowerShell 5.1 and PowerShell Core.

---

## 📂 Reorganized Workspace Layout
```
WinSuture/
 ├── WinSuture.ps1             # Main interactive dashboard launcher
 ├── optimizations.json        # Database manifest containing optimization metadata (1-20)
 ├── repairs.json              # Database manifest containing repair metadata (21-42)
 ├── backuprestore.json        # Database manifest containing backup/restore metadata (43-50)
 ├── WinSuture_Guide.md        # Comprehensive documentation guide for all 50 items
 ├── Optimizations/            # 20 standalone parameter-driven optimization scripts
 ├── Repairs/                  # 22 standalone parameter-driven system repair scripts
 └── BackupRestore/            # 8 standalone backup and restore scripts
```

---

## 🚀 How to Launch
Open **PowerShell as Administrator** and run:
```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
& ".\WinSuture.ps1"
```

For detailed explanations of all available tweaks, category mappings, and CLI settings, refer to the [WinSuture Guide](WinSuture_Guide.md).
