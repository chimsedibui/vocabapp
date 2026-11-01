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
[Registry]
; Start with Windows is set from the app; remove it on uninstall.
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "VocabApp"; ValueType: none; Flags: uninsdeletevalue dontcreatekey
[Run]
; No skipifsilent: the silent in-app update (AppUpdater) reopens the app this way.
Filename: "{app}\vocabapp.exe"; Description: "Open VocabApp"; Flags: nowait postinstall
[Code]
const
  AppMutexName = 'VocabApp.SingleInstance';

{ The app keeps running in the tray and holds this mutex. The in-app updater
  starts Setup and then quits, so a silent update waits for it to exit. }
function InitializeSetup(): Boolean;
var
  Waited: Integer;
begin
  Waited := 0;
  while CheckForMutexes(AppMutexName) do
  begin
    if WizardSilent then
    begin
      if Waited >= 60000 then
      begin
        Result := False;
        Exit;
      end;
      Sleep(500);
      Waited := Waited + 500;
    end
    else if MsgBox('VocabApp is running. Quit it from the tray icon, then click OK.',
      mbConfirmation, MB_OKCANCEL) = IDCANCEL then
    begin
      Result := False;
      Exit;
    end;
  end;
  Result := True;
end;

function InitializeUninstall(): Boolean;
begin
  Result := True;
  while Result and CheckForMutexes(AppMutexName) do
    Result := MsgBox('VocabApp is running. Quit it from the tray icon, then click OK.',
      mbConfirmation, MB_OKCANCEL) = IDOK;
end;
