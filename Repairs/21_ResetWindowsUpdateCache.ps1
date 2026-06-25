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
    $services = @("wuauserv", "bits", "cryptsvc", "msiserver")
    foreach ($svc in $services) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
        $loopCount = 0
        while ((Get-Service -Name $svc -ErrorAction SilentlyContinue).Status -ne 'Stopped' -and $loopCount -lt 15) {
            Start-Sleep -Seconds 1
            $loopCount++
        }
    }
    
    # Rename SoftwareDistribution instead of deleting it to preserve history/rollback
    $sdPath = "$env:SystemRoot\SoftwareDistribution"
    if (Test-Path $sdPath) {
        Rename-Item -Path $sdPath -NewName "SoftwareDistribution.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -Force -ErrorAction SilentlyContinue
    }
    
    # Rename Catroot2 defensively
    $catPath = "$env:SystemRoot\System32\catroot2"
    if (Test-Path $catPath) {
        Rename-Item -Path $catPath -NewName "catroot2.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -Force -ErrorAction SilentlyContinue
    }
    
    foreach ($svc in $services) {
        Start-Service -Name $svc -ErrorAction SilentlyContinue
    }
}
