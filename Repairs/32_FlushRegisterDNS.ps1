param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return $true
}
elseif ($Mode -eq "Apply") {
    ipconfig /flushdns | Out-Null
    ipconfig /registerdns | Out-Null
}
