#define AppName "Kolori"
#define AppVersion "0.4.0"
#define AppPublisher "neroist"
#define AppURL "https://github.com/neroist/kolori"
#define AppPublisherURL "https://github.com/neroist"
#define AppUpdatesURL "https://github.com/neroist/kolori/releases"
#define AppSupportURL "https://github.com/neroist/kolori/issues/new"
#define AppReadmeFile "https://github.com/neroist/kolori/blob/main/README.md"
#define AppExeName "kolori.exe"
#expr EmitLanguagesSection

[Setup]
AppId={{7BB33C94-D741-4F97-A1B0-2FEFD9B7509E}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppPublisherURL}
AppUpdatesURL={#AppUpdatesURL}
AppSupportURL={#AppSupportURL}
AppReadmeFile={#AppReadmeFile}
DefaultDirName={autopf}\{#AppName}
UninstallDisplayIcon={app}\{#AppExeName}
; "ArchitecturesAllowed=x64compatible" specifies that Setup cannot run
; on anything but x64 and Windows 11 on Arm.
ArchitecturesAllowed=x64compatible
; "ArchitecturesInstallIn64BitMode=x64compatible" requests that the
; install be done in "64-bit mode" on x64 or Windows 11 on Arm,
; meaning it should use the native 64-bit Program Files directory and
; the 64-bit view of the registry.
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
InfoAfterFile=thankyou.txt
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=commandline
OutputBaseFilename=kolori-x86_64
SolidCompression=yes
WizardStyle=modern dynamic

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\..\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\..\SDL3.dll"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

