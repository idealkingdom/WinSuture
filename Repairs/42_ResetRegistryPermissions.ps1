param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    # Scan logic: returns $true to be always selectable / checkable
    return $true
}
elseif ($Mode -eq "Apply") {
    Write-Host "[*] Resetting core registry keys permissions to defaults..."
    try {
        # Configure registry security using the default template via secedit
        secedit /configure /db $env:windir\security\database\defltbase.sdb /cfg $env:windir\inf\defltbase.inf /areas REGKEYS | Out-Null
        Write-Host "[+] Registry permissions reset successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to reset registry permissions: $_"
    }
}
