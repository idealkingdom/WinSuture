param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply", "Disable")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    $activeGuid = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Select-Object -First 1).InterfaceAlias
    $adapter = Get-NetAdapter -Name $activeGuid -ErrorAction SilentlyContinue
    if ($adapter) {
        $guid = $adapter.InterfaceGuid
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        return (Get-ItemProperty -Path $path -Name "TcpAckFrequency" -ErrorAction SilentlyContinue).TcpAckFrequency -ne 1
    } else { return $false }
}
elseif ($Mode -eq "Apply") {
    $activeGuid = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Select-Object -First 1).InterfaceAlias
    $adapter = Get-NetAdapter -Name $activeGuid -ErrorAction SilentlyContinue
    if ($adapter) {
        $guid = $adapter.InterfaceGuid
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        Set-ItemProperty -Path $path -Name "TcpAckFrequency" -Value 1 -Type DWORD -Force | Out-Null
        Set-ItemProperty -Path $path -Name "TcpDelAckTicks" -Value 0 -Type DWORD -Force | Out-Null
    }
}
elseif ($Mode -eq "Disable") {
    $activeGuid = (Get-NetRoute | Where-Object { $_.DestinationPrefix -eq '0.0.0.0/0' } | Select-Object -First 1).InterfaceAlias
    $adapter = Get-NetAdapter -Name $activeGuid -ErrorAction SilentlyContinue
    if ($adapter) {
        $guid = $adapter.InterfaceGuid
        $path = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces\$guid"
        Remove-ItemProperty -Path $path -Name "TcpAckFrequency" -ErrorAction SilentlyContinue | Out-Null
        Remove-ItemProperty -Path $path -Name "TcpDelAckTicks" -ErrorAction SilentlyContinue | Out-Null
    }
}
