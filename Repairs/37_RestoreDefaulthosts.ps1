param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $hosts = Get-Content -Path "$env:SystemRoot\System32\drivers\etc\hosts" -ErrorAction SilentlyContinue
    $lines = $hosts | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith("#") }
    $custom = $lines | Where-Object { $_ -notmatch 'localhost' -and $_ -notmatch '127.0.0.1' -and $_ -notmatch '::1' }
    return $custom.Count -gt 0
}
elseif ($Mode -eq "Apply") {
    Set-Content -Path "$env:SystemRoot\System32\drivers\etc\hosts" -Value "# Default Windows Hosts file`r`n127.0.0.1 localhost`r`n::1 localhost"
}
