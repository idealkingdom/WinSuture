param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ChildItem -Path "$env:SystemRoot\System32\Spool\Printers" -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
}
elseif ($Mode -eq "Apply") {
    Stop-Service -Name "spooler" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\System32\Spool\Printers\*.*" -Force -ErrorAction SilentlyContinue
    Start-Service -Name "spooler" -ErrorAction SilentlyContinue
}
