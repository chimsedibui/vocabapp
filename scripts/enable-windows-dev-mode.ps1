# Enables Windows Developer Mode's local development flag for Flutter symlinks.
# Run from an elevated Windows PowerShell. Does not enable Device Portal.
$ErrorActionPreference = 'Stop'
$path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock'
New-Item -Path $path -Force | Out-Null
New-ItemProperty -Path $path -Name AllowDevelopmentWithoutDevLicense -Value 1 -PropertyType DWord -Force | Out-Null
if ((Get-ItemPropertyValue -Path $path -Name AllowDevelopmentWithoutDevLicense) -ne 1) { throw 'Developer Mode was not enabled.' }
Write-Output 'Windows Developer Mode enabled for local development.'
