param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Check", "Apply")]
    [string]$Mode
)

if ($Mode -eq "Check") {
    return (Get-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -ErrorAction SilentlyContinue).DisableSearchBoxSuggestions -ne 1
}
elseif ($Mode -eq "Apply") {
    if (-not (Test-Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer")) { New-Item -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Force | Out-Null }
    Set-ItemProperty -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1 -Type DWORD -Force | Out-Null
}
