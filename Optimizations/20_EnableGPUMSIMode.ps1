param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    $needsMsi = $false
    foreach ($gpu in $gpus) {
        $pnpId = $gpu.PNPDeviceID
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $path) {
            if ((Get-ItemProperty -Path $path -Name "MSISupported" -ErrorAction SilentlyContinue).MSISupported -ne 1) { $needsMsi = $true }
        }
    }
    return $needsMsi
}
elseif ($Mode -eq "Apply") {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($gpu in $gpus) {
        $pnpId = $gpu.PNPDeviceID
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
        Set-ItemProperty -Path $path -Name "MSISupported" -Value 1 -Type DWORD -Force | Out-Null
    }
}
elseif ($Mode -eq "Disable") {
    $gpus = Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue
    foreach ($gpu in $gpus) {
        $pnpId = $gpu.PNPDeviceID
        $path = "HKLM:\SYSTEM\CurrentControlSet\Enum\$pnpId\Device Parameters\Interrupt Management\MessageSignaledInterruptProperties"
        if (Test-Path $path) {
            Set-ItemProperty -Path $path -Name "MSISupported" -Value 0 -Type DWORD -Force | Out-Null
        }
    }
}
