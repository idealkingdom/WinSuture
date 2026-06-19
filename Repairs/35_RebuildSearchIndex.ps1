param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return $false
}
elseif ($Mode -eq "Apply") {
    Stop-Service -Name "wsearch" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:ProgramData\Microsoft\Search\Data\Applications\Windows\Windows.edb" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "wsearch" -ErrorAction SilentlyContinue
}
