# Dot-source in a native Windows PowerShell: . .\scripts\dev-env.ps1
$flutterBin = Join-Path $env:USERPROFILE 'develop\flutter\bin'
if (-not (Test-Path (Join-Path $flutterBin 'flutter.bat'))) { throw "Flutter SDK not found: $flutterBin" }
$env:PATHEXT = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC'
$env:Path = $flutterBin + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
Write-Output "Windows Flutter ready: $flutterBin"
# Android SDK is installed separately in WSL; do not point native Flutter at the Linux SDK.
