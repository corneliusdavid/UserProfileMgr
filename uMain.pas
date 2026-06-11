unit uMain;

{
  Main window: lets the user pick a folder, lists the user-profile virtual disks
  it contains (file name, resolved user name, last-accessed time and size) in a
  VirtualStringTree grid with click-to-sort columns, and on double-click mounts
  the disk and opens the explorer view for drill-down, then unmount / delete.

  The grid (vstProfiles) is a design-time TVirtualStringTree. Its columns,
  options, sort and event bindings live in the .dfm; only Images (the live
  system image list) and NodeDataSize (platform-dependent) are set in code.
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls,
  Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.FileCtrl, Vcl.ImgList,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.Header, VirtualTrees.BaseTree,
  uProfileScan, VirtualTrees.BaseAncestorVCL, VirtualTrees.AncestorVCL, Vcl.Buttons, Vcl.TitleBarCtrls, LayoutSaver;

type
  PProfileRec = ^TProfileRec;
  TProfileRec = record
    Item: TProfileItem;     // reference; FProfiles owns the object
  end;

  TfrmMain = class(TForm)
    pnlTop: TPanel;
    lblFolder: TLabel;
    edtFolder: TEdit;
    btnBrowse: TButton;
    btnRefresh: TButton;
    sbStatus: TStatusBar;
    vstProfiles: TVirtualStringTree;
    btnAbout: TSpeedButton;
    ccRegistryLayoutSaver: TccRegistryLayoutSaver;
    procedure btnAboutClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure btnBrowseClick(Sender: TObject);
    procedure btnRefreshClick(Sender: TObject);
    procedure edtFolderChange(Sender: TObject);
    procedure FormActivate(Sender: TObject);
    procedure vstProfilesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure vstProfilesGetImageIndex(Sender: TBaseVirtualTree;
      Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
      var Ghosted: Boolean; var ImageIndex: TImageIndex);
    procedure vstProfilesCompareNodes(Sender: TBaseVirtualTree;
      Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
    procedure vstProfilesDblClick(Sender: TObject);
  private
    FFirstTime: Boolean;
    FProfiles: TProfileList;
    FImages: TImageList;
    FVhdxIcon: Integer;
    procedure LoadFolder(const AFolder: string);
    procedure PopulateGrid;
    procedure OpenProfile(AItem: TProfileItem);
  end;

var
  frmMain: TfrmMain;

implementation

{$R *.dfm}

uses
  System.IOUtils, System.Math, System.UITypes, uShellUtils, uVHDX, uExplorer;

const
  REG_LastFolderKey = 'LastProfileFolder';

procedure TfrmMain.btnAboutClick(Sender: TObject);
begin
  ShowMessage('User Profile Disk Manager' + sLineBreak +
              'Open source by Cornelius Concepts, LLC' + sLineBreak +
              'github.com/corneliusdavid/UserProfileMgr');
end;

procedure TfrmMain.FormCreate(Sender: TObject);
var
  Dummy: string;
begin
  FProfiles := TProfileList.Create(True);
  FImages := CreateSystemImageList(Self);
  GetShellInfo('x.vhdx', False, FVhdxIcon, Dummy);
  vstProfiles.Images := FImages;
  vstProfiles.NodeDataSize := SizeOf(TProfileRec);
  FFirstTime := True;
end;

procedure TfrmMain.FormDestroy(Sender: TObject);
begin
  FProfiles.Free;
end;

procedure TfrmMain.btnBrowseClick(Sender: TObject);
var
  Dir: string;
begin
  Dir := edtFolder.Text;
  if SelectDirectory('Select the folder that contains the user profile disks:',
    '', Dir, [sdNewUI, sdNewFolder], Self) then
    LoadFolder(Dir);
end;

procedure TfrmMain.btnRefreshClick(Sender: TObject);
begin
  if edtFolder.Text <> '' then
    LoadFolder(edtFolder.Text);
end;

procedure TfrmMain.edtFolderChange(Sender: TObject);
begin
  ccRegistryLayoutSaver.SaveStrValue(REG_LastFolderKey, edtFolder.Text);
end;

procedure TfrmMain.FormActivate(Sender: TObject);
begin
  if FFirstTime then begin
    FFirstTime := False;

    edtFolder.Text := ccRegistryLayoutSaver.RestoreStrValue(REG_LastFolderKey, EmptyStr);
    if Length(Trim(edtFolder.Text)) > 0 then
      LoadFolder(edtFolder.Text);
  end;
end;

procedure TfrmMain.LoadFolder(const AFolder: string);
var
  NewList: TProfileList;
begin
  Screen.Cursor := crHourGlass;
  try
    NewList := ScanFolder(AFolder);
    FProfiles.Free;
    FProfiles := NewList;
    edtFolder.Text := AFolder;
    PopulateGrid;
  finally
    Screen.Cursor := crDefault;
  end;
end;

procedure TfrmMain.PopulateGrid;
var
  Item: TProfileItem;
  Node: PVirtualNode;
  Rec: PProfileRec;
begin
  vstProfiles.BeginUpdate;
  try
    vstProfiles.Clear;
    for Item in FProfiles do
    begin
      Node := vstProfiles.AddChild(nil);
      Rec := vstProfiles.GetNodeData(Node);
      Rec.Item := Item;
    end;
  finally
    vstProfiles.EndUpdate;
  end;

  vstProfiles.SortTree(vstProfiles.Header.SortColumn,
    vstProfiles.Header.SortDirection);

  sbStatus.SimpleText := Format(' %d profile disk(s) in %s',
    [FProfiles.Count, edtFolder.Text]);
end;

procedure TfrmMain.vstProfilesGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Item: TProfileItem;
begin
  Item := PProfileRec(Sender.GetNodeData(Node)).Item;
  case Column of
    0: CellText := Item.FileName;
    1: CellText := Item.UserName;
    2: CellText := FormatDateTime('yyyy-mm-dd hh:nn:ss', Item.LastAccess);
    3: CellText := Format('%.1f MB', [Item.SizeBytes / (1024 * 1024)]);
  else
    CellText := '';
  end;
end;

procedure TfrmMain.vstProfilesGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex);
begin
  if (Column <= 0) and (Kind in [ikNormal, ikSelected]) then
    ImageIndex := FVhdxIcon;
end;

procedure TfrmMain.vstProfilesCompareNodes(Sender: TBaseVirtualTree;
  Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
var
  A, B: TProfileItem;
begin
  A := PProfileRec(Sender.GetNodeData(Node1)).Item;
  B := PProfileRec(Sender.GetNodeData(Node2)).Item;
  case Column of
    0: Result := AnsiCompareText(A.FileName, B.FileName);
    1: Result := AnsiCompareText(A.UserName, B.UserName);
    2: Result := CompareValue(A.LastAccess, B.LastAccess);
    3: Result := CompareValue(A.SizeBytes, B.SizeBytes);
  else
    Result := 0;
  end;
end;

procedure TfrmMain.vstProfilesDblClick(Sender: TObject);
var
  Node: PVirtualNode;
begin
  Node := vstProfiles.FocusedNode;
  if Node <> nil then
    OpenProfile(PProfileRec(vstProfiles.GetNodeData(Node)).Item);
end;

procedure TfrmMain.OpenProfile(AItem: TProfileItem);
var
  Disk: TVirtualDisk;
  Action: TExplorerAction;
begin
  Disk := TVirtualDisk.Create(AItem.FullPath);
  try
    sbStatus.SimpleText := ' Mounting ' + AItem.FileName + ' ...';
    Update;
    try
      Disk.Mount;
    except
      on E: Exception do
      begin
        MessageDlg('Unable to mount the profile disk:'#13#10#13#10 + E.Message,
          mtError, [mbOK], 0);
        sbStatus.SimpleText := ' Mount failed.';
        Exit;
      end;
    end;

    TfrmExplorer.Execute(Self, AItem.UserName, Disk.DriveRoot, AItem.FileName,
      Action);

    // Always detach before we leave - releases the file handle.
    Disk.Unmount;

    if Action = eaDelete then
    begin
      try
        TFile.Delete(AItem.FullPath);
        sbStatus.SimpleText := ' Deleted ' + AItem.FileName;
        LoadFolder(edtFolder.Text);     // refresh the grid
      except
        on E: Exception do
          MessageDlg('The disk was unmounted but the file could not be '
            + 'deleted:'#13#10#13#10 + E.Message, mtError, [mbOK], 0);
      end;
    end
    else
      sbStatus.SimpleText := ' Unmounted ' + AItem.FileName;
  finally
    Disk.Free;
  end;
end;

end.
