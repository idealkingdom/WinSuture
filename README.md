# 🛡️ WinSuture

WinSuture is a modular, parameters-driven interactive CLI suite built for Windows 10 and 11 power users. It offers a single dashboard containing **20 advanced performance optimizations**, **22 critical system repairs**, and **8 automated backup/restore utilities**.

The entire tool is designed to run locally (fully offline) if the subfolders are present in the workspace, or fall back to dynamically streaming component script blocks directly from GitHub endpoints if running standalone.

---

## ⚡ Key Highlights
* **Category Groupings**: All tweaks and repairs are categorized cleanly under descriptive subheaders (e.g. `Gaming`, `Networking`, `System UI`) inside a dual-column interactive dashboard.
* **Precedence Safety**: Backup tasks (creating restore points, registry exports, hosts backups) are prioritized and execute *first* before any system modifications are run.
* **Safe Mode Guard**: Detects if the system is running in Windows Normal Mode and prompts a warning detailing the benefits of Safe Mode before allowing you to proceed.
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
