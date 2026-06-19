param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "WSearch" -ErrorAction SilentlyContinue).StartType -ne "Disabled"
}
elseif ($Mode -eq "Apply") {
    sc.exe config WSearch start= disabled | Out-Null
    Stop-Service -Name "WSearch" -Force -ErrorAction SilentlyContinue
}
