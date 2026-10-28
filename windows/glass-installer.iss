#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef DistDir
  #error DistDir is required
#endif
[Setup]
AppId={{1A39CB64-0A5B-478E-9590-978614C804A8}
AppName=Venera Glass
AppVersion={#AppVersion}
AppPublisher=ltt2077
AppPublisherURL=https://github.com/ltt2077/venera
DefaultDirName={autopf}\Venera
DefaultGroupName=Venera
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#DistDir}
OutputBaseFilename=venera-{#AppVersion}-windows-x64-setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\venera.exe
[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{autoprograms}\Venera Glass"; Filename: "{app}\venera.exe"
[Run]
Filename: "{app}\venera.exe"; Description: "Launch Venera Glass"; Flags: nowait postinstall skipifsilent
