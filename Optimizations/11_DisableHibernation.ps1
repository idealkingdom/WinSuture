param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Power" -Name "HibernateEnabled" -ErrorAction SilentlyContinue).HibernateEnabled -ne 0
}
elseif ($Mode -eq "Apply") {
    powercfg -h off
}
elseif ($Mode -eq "Disable") {
    powercfg -h on
}
