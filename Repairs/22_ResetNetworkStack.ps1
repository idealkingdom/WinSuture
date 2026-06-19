param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Test-Connection -ComputerName "google.com" -Count 1 -Delay 1 -ErrorAction SilentlyContinue) -eq $null
}
elseif ($Mode -eq "Apply") {
    netsh winsock reset | Out-Null
    netsh int ip reset | Out-Null
}
