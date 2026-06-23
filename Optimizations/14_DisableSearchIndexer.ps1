param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "WSearch" -ErrorAction SilentlyContinue).StartType -ne "Disabled"
}
elseif ($Mode -eq "Apply") {
    sc.exe config WSearch start= disabled | Out-Null
    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
}
elseif ($Mode -eq "Disable") {
    sc.exe config WSearch start= Delayed-Auto | Out-Null
    Start-Service -Name "WSearch" -ErrorAction SilentlyContinue
}
