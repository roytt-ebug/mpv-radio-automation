#ifndef AppFiles
  #error AppFiles must point to the compiled application folder.
#endif
#ifndef ArtifactDir
  #error ArtifactDir must point to the output folder.
#endif

[Setup]
AppId={{AB9A4557-CEAB-4FA8-9044-5330EF7175DE}
AppName=Automatic Music
AppVersion=0.2.0-beta.2
AppVerName=Automatic Music 0.2.0 beta 2
AppPublisher=Automatic Music contributors
AppPublisherURL=https://github.com/roytt-ebug/mpv-radio-automation
AppSupportURL=https://github.com/roytt-ebug/mpv-radio-automation/issues
AppUpdatesURL=https://github.com/roytt-ebug/mpv-radio-automation/releases
VersionInfoVersion=0.2.1.0
DefaultDirName={localappdata}\Programs\Automatic Music
DefaultGroupName=Automatic Music
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64os
ArchitecturesInstallIn64BitMode=x64os
MinVersion=10.0.19041
OutputDir={#ArtifactDir}
OutputBaseFilename=Automatic-Music-Setup-0.2.0-beta.2
SetupIconFile={#AppFiles}\AutomaticMusic.ico
UninstallDisplayIcon={app}\AutomaticMusic.exe
WizardStyle=modern
Compression=lzma2
SolidCompression=yes
AppMutex=AutomaticMusic.Desktop
CloseApplications=no
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "{#AppFiles}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Automatic Music"; Filename: "{app}\AutomaticMusic.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Automatic Music"; Filename: "{app}\AutomaticMusic.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\AutomaticMusic.exe"; Parameters: "--setup"; Description: "Open Automatic Music and set up playback"; Flags: nowait postinstall skipifsilent

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ExitCode: Integer;
  ExistingApp: String;
begin
  Result := '';
  ExistingApp := ExpandConstant('{app}\AutomaticMusic.exe');
  if FileExists(ExistingApp) then
  begin
    if not Exec(ExistingApp, '--stop', ExpandConstant('{app}'), SW_HIDE,
      ewWaitUntilTerminated, ExitCode) then
      Result := 'The previous Automatic Music player could not be stopped. Close it and try again.'
    else if ExitCode <> 0 then
      Result := 'Automatic Music could not stop its player safely. Open the app, click Stop, and try again.';
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ExitCode: Integer;
  AppFile: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    AppFile := ExpandConstant('{app}\AutomaticMusic.exe');
    if FileExists(AppFile) then
    begin
      if not Exec(AppFile, '--uninstall', ExpandConstant('{app}'), SW_HIDE,
        ewWaitUntilTerminated, ExitCode) then
      begin
        SuppressibleMsgBox('Automatic Music could not remove its schedules. Reinstall the app to repair it, then uninstall again. Your files have been kept.', mbError, MB_OK, IDOK);
        Abort;
      end;
      if ExitCode <> 0 then
      begin
        SuppressibleMsgBox('Automatic Music could not safely remove its schedules. See the app log in your Automatic Music data folder. Your files have been kept.', mbError, MB_OK, IDOK);
        Abort;
      end;
    end
    else
    begin
      SuppressibleMsgBox('The Automatic Music executable is missing, so its schedules cannot be removed safely. Run the installer to repair the app, then uninstall again.', mbError, MB_OK, IDOK);
      Abort;
    end;
  end;
end;
