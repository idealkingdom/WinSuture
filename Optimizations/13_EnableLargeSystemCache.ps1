param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -ErrorAction SilentlyContinue).LargeSystemCache -ne 1
}
elseif ($Mode -eq "Apply") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 1 -Type DWORD -Force | Out-Null
}
elseif ($Mode -eq "Disable") {
    Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "LargeSystemCache" -Value 0 -Type DWORD -Force | Out-Null
}
