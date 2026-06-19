param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $dir = "$env:SystemRoot\SoftwareDistribution"
    return (Test-Path $dir) -and ((Get-ChildItem $dir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum -gt 1GB)
}
elseif ($Mode -eq "Apply") {
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "bits" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "cryptsvc" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\SoftwareDistribution" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\System32\catroot2" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    Start-Service -Name "bits" -ErrorAction SilentlyContinue
    Start-Service -Name "cryptsvc" -ErrorAction SilentlyContinue
}
