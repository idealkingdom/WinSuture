param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return ((Get-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -ErrorAction SilentlyContinue).GameDVR_Enabled -ne 0) -or ((Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -ErrorAction SilentlyContinue).AppCaptureEnabled -ne 0)
}
elseif ($Mode -eq "Apply") {
    Set-ItemProperty -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0 -Type DWORD -Force | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0 -Type DWORD -Force | Out-Null
}
