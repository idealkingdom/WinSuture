param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $needsTweak = $false
    
    # Check Widgets (Dsh / AllowNewsAndInterests)
    $widgetsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (Test-Path $widgetsPath) {
        $val = (Get-ItemProperty -Path $widgetsPath -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue).AllowNewsAndInterests
        if ($null -eq $val -or $val -ne 0) { $needsTweak = $true }
    } else {
        $needsTweak = $true
    }
    
    # Check Chat (Windows Chat / ChatIcon)
    $chatPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"
    if (Test-Path $chatPath) {
        $val = (Get-ItemProperty -Path $chatPath -Name "ChatIcon" -ErrorAction SilentlyContinue).ChatIcon
        if ($null -eq $val -or $val -ne 3) { $needsTweak = $true }
    } else {
        $needsTweak = $true
    }
    
    return $needsTweak
}
elseif ($Mode -eq "Apply") {
    # 1. Disable Widgets (News and Interests)
    $widgetsPath = "HKLM:\SOFTWARE\Policies\Microsoft\Dsh"
    if (-not (Test-Path $widgetsPath)) { New-Item -Path $widgetsPath -Force | Out-Null }
    Set-ItemProperty -Path $widgetsPath -Name "AllowNewsAndInterests" -Value 0 -Type DWORD -Force | Out-Null
    
    # 2. Disable Taskbar Chat Icon
    $chatPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat"
    if (-not (Test-Path $chatPath)) { New-Item -Path $chatPath -Force | Out-Null }
    Set-ItemProperty -Path $chatPath -Name "ChatIcon" -Value 3 -Type DWORD -Force | Out-Null
    
    # 3. Restart Explorer to apply UI changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
elseif ($Mode -eq "Disable") {
    # 1. Enable Widgets (News and Interests)
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -ErrorAction SilentlyContinue | Out-Null
    
    # 2. Enable Taskbar Chat Icon
    Remove-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Chat" -Name "ChatIcon" -ErrorAction SilentlyContinue | Out-Null
    
    # 3. Restart Explorer to apply UI changes
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
}
