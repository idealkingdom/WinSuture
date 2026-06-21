param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (powercfg -list | Select-String "Ultimate Performance") -eq $null
}
elseif ($Mode -eq "Apply") {
    powercfg -duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null
}
elseif ($Mode -eq "Disable") {
    powercfg -delete e9a42b02-d5df-448d-aa00-03f14749eb61 2>$null | Out-Null
}
