# Run in native Windows PowerShell. May require an administrator's UAC approval.
$ErrorActionPreference = 'Stop'
$env:PATHEXT = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC'
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vswhere) {
    $installed = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($installed) { Write-Output "C++ build tools already installed: $installed"; exit 0 }
}
$installer = Join-Path $env:TEMP 'vocabapp-vs-BuildTools.exe'
Invoke-WebRequest -Uri 'https://aka.ms/vs/17/release/vs_BuildTools.exe' -OutFile $installer
if ((Get-AuthenticodeSignature $installer).Status -ne 'Valid') { throw 'Installer signature is invalid.' }
$proc = Start-Process -FilePath $installer -ArgumentList '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' -PassThru -Wait
if ($proc.ExitCode -notin @(0,3010)) { throw "Installer failed: $($proc.ExitCode)" }
if ($proc.ExitCode -eq 3010) { Write-Output 'Windows requests a restart; restart manually when convenient.' }
