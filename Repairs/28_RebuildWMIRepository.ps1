param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $res = winmgmt /verifyrepository
    return $res -notmatch "consistent"
}
elseif ($Mode -eq "Apply") {
    Stop-Service -Name "winmgmt" -Force -ErrorAction SilentlyContinue
    winmgmt /salvagerepository
    winmgmt /resetrepository
    Start-Service -Name "winmgmt" -ErrorAction SilentlyContinue
}
