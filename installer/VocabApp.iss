#define MyAppVersion GetEnv("VERSION")
#if MyAppVersion == ""
  #error VERSION environment variable is required
#endif
[Setup]
AppId={{61B1FA72-4961-40B8-82C2-05D3B54DE809}
AppName=VocabApp
AppVersion={#MyAppVersion}
AppPublisher=VocabApp
AppPublisherURL=https://github.com/chimsedibui/vocabapp
AppUpdatesURL=https://github.com/chimsedibui/vocabapp/releases/latest
DefaultDirName={localappdata}\Programs\VocabApp
DefaultGroupName=VocabApp
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\artifacts
OutputBaseFilename=VocabApp-{#MyAppVersion}-Setup
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\vocabapp.exe
[Tasks]
Name: desktopicon; Description: "Create a desktop shortcut"; Flags: unchecked
[Files]
Source: "..\app\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\VocabApp"; Filename: "{app}\vocabapp.exe"
Name: "{autodesktop}\VocabApp"; Filename: "{app}\vocabapp.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\vocabapp.exe"; Description: "Open VocabApp"; Flags: nowait postinstall skipifsilent
