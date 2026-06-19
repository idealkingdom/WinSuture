param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "wuauserv" -ErrorAction SilentlyContinue).StartType -eq "Disabled"
}
elseif ($Mode -eq "Apply") {
    sc.exe config wuauserv start= demand | Out-Null
}
