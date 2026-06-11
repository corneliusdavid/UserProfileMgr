program UserProfileMgr;

uses
  Vcl.Forms,
  uMain in 'uMain.pas' {frmMain},
  uExplorer in 'uExplorer.pas' {frmExplorer},
  uVHDX in 'uVHDX.pas',
  uProfileScan in 'uProfileScan.pas',
  uShellUtils in 'uShellUtils.pas',
  Vcl.Themes,
  Vcl.Styles;

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Golden Graphite');
  Application.Title := 'User Profile Disk Manager';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
