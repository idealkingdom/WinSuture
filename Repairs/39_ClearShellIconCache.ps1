param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return $false
}
elseif ($Mode -eq "Apply") {
    ie4uinit.exe -show | Out-Null
    Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:LocalAppData\IconCache.db" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:UserProfile\AppData\Local\Microsoft\Windows\Explorer\thumbcache_*.db" -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}
