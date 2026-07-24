#define AppName "健康重启计划"
#define AppVersion "1.0.7"
#define AppPublisher "健康重启计划"
#define AppExeName "健康重启计划.exe"

[Setup]
AppId={{A49AA964-B46F-40E0-927E-F50DCA3909A8}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} 安装程序
VersionInfoProductName={#AppName}
DefaultDirName={localappdata}\Programs\HealthResetPlan
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\..\outputs
OutputBaseFilename=健康重启计划-Windows-安装版-{#AppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: checkedonce

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "启动 {#AppName}"; Flags: nowait postinstall skipifsilent

[Code]
var
  DeleteDataCheckBox: TNewCheckBox;

function InitializeUninstall(): Boolean;
begin
  DeleteDataCheckBox := TNewCheckBox.Create(UninstallProgressForm);
  DeleteDataCheckBox.Parent := UninstallProgressForm;
  DeleteDataCheckBox.Left := UninstallProgressForm.StatusLabel.Left;
  DeleteDataCheckBox.Top := UninstallProgressForm.StatusLabel.Top + 42;
  DeleteDataCheckBox.Width := UninstallProgressForm.StatusLabel.Width;
  DeleteDataCheckBox.Caption := '同时删除本机健康数据和登录信息';
  DeleteDataCheckBox.Checked := False;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if (CurUninstallStep = usPostUninstall) and DeleteDataCheckBox.Checked then
  begin
    DeleteFile(ExpandConstant('{userdocs}\health_reset_plan.sqlite'));
    DeleteFile(ExpandConstant('{userdocs}\health_reset_plan.sqlite-wal'));
    DeleteFile(ExpandConstant('{userdocs}\health_reset_plan.sqlite-shm'));
    DelTree(ExpandConstant('{userappdata}\health_reset_plan'), True, True, True);
  end;
end;
