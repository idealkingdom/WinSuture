param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -ErrorAction SilentlyContinue).StartupDelayInMSec -ne 0
}
elseif ($Mode -eq "Apply") {
    if (-not (Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize")) { New-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Force | Out-Null }
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0 -Type DWORD -Force | Out-Null
}
