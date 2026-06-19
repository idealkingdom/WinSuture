param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-Service -Name "vss" -ErrorAction SilentlyContinue).Status -ne "Running"
}
elseif ($Mode -eq "Apply") {
    Stop-Service -Name "vss" -Force -ErrorAction SilentlyContinue
    Stop-Service -Name "swprv" -Force -ErrorAction SilentlyContinue
    regsvr32 /s ole32.dll
    regsvr32 /s oleaut32.dll
    regsvr32 /s vssapi.dll
    regsvr32 /s es.dll
    regsvr32 /s stdole2.tlb
    regsvr32 /s vsmgmt.dll
    Start-Service -Name "swprv" -ErrorAction SilentlyContinue
    Start-Service -Name "vss" -ErrorAction SilentlyContinue
}
