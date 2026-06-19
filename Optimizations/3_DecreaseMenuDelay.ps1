param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -ErrorAction SilentlyContinue).MenuShowDelay -ne "20"
}
elseif ($Mode -eq "Apply") {
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "20" -Type String -Force | Out-Null
}
