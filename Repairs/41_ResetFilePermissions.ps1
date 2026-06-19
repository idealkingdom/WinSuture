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
    Write-Host "[*] Resetting system file permissions to defaults... (This may take a few minutes)"
    try {
        # Configure file security using the default template via secedit
        secedit /configure /db $env:windir\security\database\defltbase.sdb /cfg $env:windir\inf\defltbase.inf /areas FILESTORE | Out-Null
        Write-Host "[+] System file permissions reset successfully." -ForegroundColor Green
    } catch {
        Write-Error "Failed to reset file permissions: $_"
    }
}
