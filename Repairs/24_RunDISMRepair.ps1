param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $res = DISM /Online /Cleanup-Image /CheckHealth
    return ($res | Select-String "corruption") -ne $null
}
elseif ($Mode -eq "Apply") {
    DISM /Online /Cleanup-Image /RestoreHealth
}
