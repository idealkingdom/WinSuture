param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Test-Path "$env:SystemRoot\System32\GroupPolicy") -or (Test-Path "$env:SystemRoot\System32\GroupPolicyUsers")
}
elseif ($Mode -eq "Apply") {
    Remove-Item -Path "$env:SystemRoot\System32\GroupPolicy" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "$env:SystemRoot\System32\GroupPolicyUsers" -Recurse -Force -ErrorAction SilentlyContinue
    gpupdate /force | Out-Null
}
