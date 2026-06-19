param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return $true
}
elseif ($Mode -eq "Apply") {
    sfc /scannow
}
