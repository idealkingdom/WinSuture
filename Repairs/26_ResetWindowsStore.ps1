param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return $false
}
elseif ($Mode -eq "Apply") {
    wsreset.exe
}
