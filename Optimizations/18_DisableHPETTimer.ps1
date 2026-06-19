param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (bcdedit /enum | Select-String "useplatformclock") -ne $null
}
elseif ($Mode -eq "Apply") {
    bcdedit /deletevalue useplatformclock 2>$null
    bcdedit /set disabledynamictick yes 2>$null
}
