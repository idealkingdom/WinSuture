param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "DiagTrack" -ErrorAction SilentlyContinue).StartType -ne "Disabled"
}
elseif ($Mode -eq "Apply") {
    sc.exe config DiagTrack start= disabled | Out-Null
    Stop-Service -Name "DiagTrack" -Force -ErrorAction SilentlyContinue
}
