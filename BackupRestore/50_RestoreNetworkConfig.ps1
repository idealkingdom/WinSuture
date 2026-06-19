param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true to be always selectable
    return $true
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Resetting Winsock catalog and IP stack defaults..."
    try {
        Write-Host "  Resetting Winsock catalog..."
        netsh winsock reset | Out-Null
        Write-Host "  Resetting TCP/IP stack settings..."
        netsh int ip reset | Out-Null
        Write-Host "  Flushing DNS client cache..."
        Clear-DnsClientCache -ErrorAction SilentlyContinue
        Write-Host "  Registering DNS connections..."
        ipconfig /registerdns | Out-Null
        Write-Host "[+] Network stack reset completed successfully." -ForegroundColor Green
        Write-Host "[*] Note: A reboot is required to activate the new Winsock catalog mappings." -ForegroundColor Yellow
    } catch {
        Write-Error "Failed to fully restore default network configuration: $_"
    }
}
