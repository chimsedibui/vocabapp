param(
    [string]$BuildRoot = (Join-Path $env:USERPROFILE 'develop\VocabApp-build')
)
$ErrorActionPreference = 'Stop'
$repository = Split-Path $PSScriptRoot -Parent
$source = Join-Path $repository 'app'
$marker = Join-Path $BuildRoot '.vocabapp-build-workspace'
if ((Test-Path $BuildRoot) -and -not (Test-Path $marker)) {
    throw "Refusing to overwrite an unowned build directory: $BuildRoot"
}
New-Item -ItemType Directory -Force -Path $BuildRoot | Out-Null
Set-Content -Path $marker -Value $source
$destination = Join-Path $BuildRoot 'app'
$flutter = Join-Path $env:USERPROFILE 'develop\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) { throw 'Windows Flutter SDK not found.' }
$env:PATHEXT = '.COM;.EXE;.BAT;.CMD;.VBS;.VBE;.JS;.JSE;.WSF;.WSH;.MSC'
$env:Path = (Split-Path $flutter -Parent) + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
# Mirror only inside this marked build workspace, never back into the source.
& robocopy.exe $source $destination /MIR /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XD .git .dart_tool build .gradle .idea ephemeral /XF local.properties .flutter-plugins-dependencies *.jks *.keystore key.properties
if ($LASTEXITCODE -ge 8) { throw "Source copy failed: $LASTEXITCODE" }
Push-Location $destination
try {
    $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    & $cmd /d /c ('call "{0}" pub get' -f $flutter)
    if ($LASTEXITCODE -ne 0) { throw 'Windows dependency setup failed.' }
    & $cmd /d /c ('call "{0}" build windows --release --no-pub' -f $flutter)
    if ($LASTEXITCODE -ne 0) { throw 'Windows release build failed.' }
    $versionLine = (Get-Content pubspec.yaml | Select-String '^version:').Line
    $version = ($versionLine -replace '^version:\s*', '').Split('+')[0].Trim()
    $artifacts = Join-Path $repository 'artifacts'
    New-Item -ItemType Directory -Force -Path $artifacts | Out-Null
    $archive = Join-Path $artifacts "VocabApp-$version-windows-x64.zip"
    Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath $archive -Force
    $hash = (Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant()
    "$hash  $(Split-Path $archive -Leaf)" | Set-Content -Encoding ascii "$archive.sha256"
    Write-Output "Windows archive: $archive"
} finally { Pop-Location }
