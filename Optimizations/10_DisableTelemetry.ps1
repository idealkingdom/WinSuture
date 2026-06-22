param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "DiagTrack" -ErrorAction SilentlyContinue).StartType -ne "Disabled"
}
elseif ($Mode -eq "Apply") {
    sc.exe config DiagTrack start= disabled | Out-Null
    Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
}
elseif ($Mode -eq "Disable") {
    sc.exe config DiagTrack start= auto | Out-Null
    Start-Service -Name "DiagTrack" -ErrorAction SilentlyContinue
}
