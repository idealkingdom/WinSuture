param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return Test-Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.lnk\UserChoice"
}
elseif ($Mode -eq "Apply") {
    Remove-Item -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\.lnk\UserChoice" -Force -ErrorAction SilentlyContinue
}
