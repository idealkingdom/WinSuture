param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (bcdedit /enum | Select-String "useplatformclock") -ne $null
}
elseif ($Mode -eq "Apply") {
    bcdedit /deletevalue useplatformclock 2>$null
    bcdedit /set disabledynamictick yes 2>$null
}
elseif ($Mode -eq "Disable") {
    bcdedit /set useplatformclock yes 2>$null | Out-Null
    bcdedit /deletevalue disabledynamictick 2>$null | Out-Null
}
