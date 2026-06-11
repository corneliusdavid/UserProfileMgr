unit uExplorer;

{
  Explorer view shown after a profile disk is mounted. A VirtualStringTree on
  the left (vstTree) shows the folder hierarchy, lazily populated from the file
  system; a second VirtualStringTree on the right (vstFiles) lists the contents
  of the selected folder. The user drills into sub-folders, then Unmount/Delete.

  Both trees are design-time components; their columns, options and event
  bindings live in the .dfm. Images (live system image list) and NodeDataSize
  (platform-dependent) are set in code. The form does not mount/unmount - it
  returns the chosen action to the caller (the main form owns the disk).
}

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ExtCtrls,
  Vcl.StdCtrls, Vcl.ImgList,
  VirtualTrees, VirtualTrees.Types, VirtualTrees.Header, VirtualTrees.BaseTree,
  uShellUtils, VirtualTrees.BaseAncestorVCL, VirtualTrees.AncestorVCL;

type
  TExplorerAction = (eaUnmount, eaDelete);

  PFolderRec = ^TFolderRec;
  TFolderRec = record
    Path: string;
    Name: string;
  end;

  PFileRec = ^TFileRec;
  TFileRec = record
    Entry: TFileEntry;
  end;

  TfrmExplorer = class(TForm)
    pnlTop: TPanel;
    lblHeader: TLabel;
    pnlBottom: TPanel;
    btnUnmount: TButton;
    btnDelete: TButton;
    splMain: TSplitter;
    vstTree: TVirtualStringTree;
    vstFiles: TVirtualStringTree;
    procedure FormCreate(Sender: TObject);
    procedure btnUnmountClick(Sender: TObject);
    procedure btnDeleteClick(Sender: TObject);
    // Folder tree events
    procedure vstTreeFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure vstTreeGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure vstTreeGetImageIndex(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Kind: TVTImageKind; Column: TColumnIndex; var Ghosted: Boolean;
      var ImageIndex: TImageIndex);
    procedure vstTreeExpanding(Sender: TBaseVirtualTree; Node: PVirtualNode;
      var Allowed: Boolean);
    procedure vstTreeFocusChanged(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex);
    // File list events
    procedure vstFilesFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure vstFilesGetText(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Column: TColumnIndex; TextType: TVSTTextType; var CellText: string);
    procedure vstFilesGetImageIndex(Sender: TBaseVirtualTree; Node: PVirtualNode;
      Kind: TVTImageKind; Column: TColumnIndex; var Ghosted: Boolean;
      var ImageIndex: TImageIndex);
    procedure vstFilesCompareNodes(Sender: TBaseVirtualTree;
      Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
    procedure vstFilesDblClick(Sender: TObject);
  private
    FAction: TExplorerAction;
    FUserName: string;
    FDriveRoot: string;
    FImages: TImageList;
    procedure AddFolderNode(AParent: PVirtualNode; const APath, AName: string);
    procedure PopulateChildren(ANode: PVirtualNode);
    procedure ShowFolder(const APath: string);
    function LocateFolder(const APath: string): PVirtualNode;
  public
    { Configures and shows the view modally. AAction returns the user's choice
      (defaults to Unmount if the window is simply closed). }
    class function Execute(AOwner: TComponent; const AUserName, ADriveRoot,
      AFileName: string; out AAction: TExplorerAction): Boolean;
  end;

implementation

{$R *.dfm}

uses
  Winapi.ShellAPI, System.Math, System.IOUtils, System.UITypes;

function FormatSize(ABytes: Int64): string;
const
  KB = Int64(1024);
  MB = KB * 1024;
  GB = MB * 1024;
begin
  if ABytes >= GB then
    Result := Format('%.2f GB', [ABytes / GB])
  else if ABytes >= MB then
    Result := Format('%.1f MB', [ABytes / MB])
  else if ABytes >= KB then
    Result := Format('%.0f KB', [ABytes / KB])
  else
    Result := Format('%d B', [ABytes]);
end;

{ TfrmExplorer }

procedure TfrmExplorer.FormCreate(Sender: TObject);
begin
  FImages := CreateSystemImageList(Self);
  vstTree.Images := FImages;
  vstTree.NodeDataSize := SizeOf(TFolderRec);
  vstFiles.Images := FImages;
  vstFiles.NodeDataSize := SizeOf(TFileRec);
end;

procedure TfrmExplorer.AddFolderNode(AParent: PVirtualNode;
  const APath, AName: string);
var
  Node: PVirtualNode;
  Rec: PFolderRec;
begin
  Node := vstTree.AddChild(AParent);
  Rec := vstTree.GetNodeData(Node);
  Rec.Path := APath;
  Rec.Name := AName;
  vstTree.HasChildren[Node] := HasSubfolders(APath);
end;

procedure TfrmExplorer.PopulateChildren(ANode: PVirtualNode);
var
  Rec: PFolderRec;
  Entries: TArray<TFileEntry>;
  E: TFileEntry;
begin
  Rec := vstTree.GetNodeData(ANode);
  Entries := ListFolder(Rec.Path, False { folders only });
  vstTree.BeginUpdate;
  try
    for E in Entries do
      AddFolderNode(ANode, E.FullPath, E.DisplayName);
  finally
    vstTree.EndUpdate;
  end;
end;

procedure TfrmExplorer.ShowFolder(const APath: string);
var
  Entries: TArray<TFileEntry>;
  E: TFileEntry;
  Node: PVirtualNode;
  Rec: PFileRec;
begin
  Entries := ListFolder(APath, True { include files });
  vstFiles.BeginUpdate;
  try
    vstFiles.Clear;
    for E in Entries do
    begin
      Node := vstFiles.AddChild(nil);
      Rec := vstFiles.GetNodeData(Node);
      Rec.Entry := E;
    end;
  finally
    vstFiles.EndUpdate;
  end;
end;

function TfrmExplorer.LocateFolder(const APath: string): PVirtualNode;
var
  Node, Child: PVirtualNode;
  Rec: PFolderRec;
  Target: string;
begin
  Result := nil;
  Target := IncludeTrailingPathDelimiter(APath).ToLower;
  Node := vstTree.GetFirst;          // root (drive)
  while Node <> nil do
  begin
    Rec := vstTree.GetNodeData(Node);
    if SameText(IncludeTrailingPathDelimiter(Rec.Path), Target) then
      Exit(Node);
    // descend into the child that is an ancestor of (or equals) the target
    if not Target.StartsWith(IncludeTrailingPathDelimiter(Rec.Path).ToLower) then
      Break;
    vstTree.Expanded[Node] := True;  // ensures children exist (vstTreeExpanding)
    Child := vstTree.GetFirstChild(Node);
    Node := nil;
    while Child <> nil do
    begin
      Rec := vstTree.GetNodeData(Child);
      if Target.StartsWith(IncludeTrailingPathDelimiter(Rec.Path).ToLower) then
      begin
        Node := Child;
        Break;
      end;
      Child := vstTree.GetNextSibling(Child);
    end;
  end;
end;

{ Folder tree events }

procedure TfrmExplorer.vstTreeFreeNode(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
begin
  Finalize(PFolderRec(Sender.GetNodeData(Node))^);
end;

procedure TfrmExplorer.vstTreeGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
begin
  CellText := PFolderRec(Sender.GetNodeData(Node)).Name;
end;

procedure TfrmExplorer.vstTreeGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex);
var
  Rec: PFolderRec;
  Idx: Integer;
  TypeName: string;
begin
  if (Column <= 0) and (Kind in [ikNormal, ikSelected]) then
  begin
    Rec := Sender.GetNodeData(Node);
    GetShellInfo(Rec.Path, True, Idx, TypeName);
    ImageIndex := Idx;
  end;
end;

procedure TfrmExplorer.vstTreeExpanding(Sender: TBaseVirtualTree;
  Node: PVirtualNode; var Allowed: Boolean);
begin
  if Sender.ChildCount[Node] = 0 then
    PopulateChildren(Node);
  Allowed := True;
end;

procedure TfrmExplorer.vstTreeFocusChanged(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex);
begin
  if Node <> nil then
    ShowFolder(PFolderRec(Sender.GetNodeData(Node)).Path);
end;

{ File list events }

procedure TfrmExplorer.vstFilesFreeNode(Sender: TBaseVirtualTree;
  Node: PVirtualNode);
begin
  Finalize(PFileRec(Sender.GetNodeData(Node))^);
end;

procedure TfrmExplorer.vstFilesGetText(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType;
  var CellText: string);
var
  Rec: PFileRec;
begin
  Rec := Sender.GetNodeData(Node);
  case Column of
    0: CellText := Rec.Entry.DisplayName;
    1: CellText := Rec.Entry.TypeName;
    2: if Rec.Entry.IsDir then CellText := ''
       else CellText := FormatSize(Rec.Entry.Size);
    3: CellText := FormatDateTime('yyyy-mm-dd hh:nn', Rec.Entry.Modified);
  else
    CellText := '';
  end;
end;

procedure TfrmExplorer.vstFilesGetImageIndex(Sender: TBaseVirtualTree;
  Node: PVirtualNode; Kind: TVTImageKind; Column: TColumnIndex;
  var Ghosted: Boolean; var ImageIndex: TImageIndex);
begin
  if (Column <= 0) and (Kind in [ikNormal, ikSelected]) then
    ImageIndex := PFileRec(Sender.GetNodeData(Node)).Entry.IconIndex;
end;

procedure TfrmExplorer.vstFilesCompareNodes(Sender: TBaseVirtualTree;
  Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
var
  A, B: PFileRec;
begin
  A := Sender.GetNodeData(Node1);
  B := Sender.GetNodeData(Node2);
  case Column of
    0: Result := AnsiCompareText(A.Entry.DisplayName, B.Entry.DisplayName);
    1: Result := AnsiCompareText(A.Entry.TypeName, B.Entry.TypeName);
    2: Result := CompareValue(A.Entry.Size, B.Entry.Size);
    3: Result := CompareValue(A.Entry.Modified, B.Entry.Modified);
  else
    Result := 0;
  end;
end;

procedure TfrmExplorer.vstFilesDblClick(Sender: TObject);
var
  Node, Found: PVirtualNode;
  Rec: PFileRec;
begin
  Node := vstFiles.FocusedNode;
  if Node = nil then
    Exit;
  Rec := vstFiles.GetNodeData(Node);
  if Rec.Entry.IsDir then
  begin
    Found := LocateFolder(Rec.Entry.FullPath);
    if Found <> nil then
    begin
      vstTree.FocusedNode := Found;
      vstTree.Selected[Found] := True;   // triggers vstTreeFocusChanged
      vstTree.ScrollIntoView(Found, False);
    end;
  end
  else
    ShellExecute(Handle, 'open', PChar(Rec.Entry.FullPath), nil, nil, SW_SHOWNORMAL);
end;

{ Buttons }

procedure TfrmExplorer.btnUnmountClick(Sender: TObject);
begin
  FAction := eaUnmount;
  ModalResult := mrOk;
end;

procedure TfrmExplorer.btnDeleteClick(Sender: TObject);
begin
  if MessageDlg(Format('Permanently delete the profile disk for "%s"?'#13#10 +
    'The disk will be unmounted and the file deleted. This cannot be undone.',
    [FUserName]), mtWarning, [mbYes, mbNo], 0) = mrYes then
  begin
    FAction := eaDelete;
    ModalResult := mrOk;
  end;
end;

class function TfrmExplorer.Execute(AOwner: TComponent; const AUserName,
  ADriveRoot, AFileName: string; out AAction: TExplorerAction): Boolean;
var
  Frm: TfrmExplorer;
begin
  Frm := TfrmExplorer.Create(AOwner);
  try
    Frm.FAction := eaUnmount;
    Frm.FUserName := AUserName;
    Frm.FDriveRoot := ADriveRoot;
    Frm.Caption := Format('Profile Disk - %s  [%s]', [AUserName, ADriveRoot]);
    Frm.lblHeader.Caption := Format('%s     |     %s     |     mounted at %s',
      [AUserName, AFileName, ADriveRoot]);

    // Seed the tree with the drive root and expand it.
    Frm.AddFolderNode(nil, ADriveRoot, ADriveRoot);
    Frm.vstTree.FocusedNode := Frm.vstTree.GetFirst;
    Frm.vstTree.Selected[Frm.vstTree.GetFirst] := True;
    Frm.vstTree.Expanded[Frm.vstTree.GetFirst] := True;

    Frm.ShowModal;
    AAction := Frm.FAction;
    Result := True;
  finally
    Frm.Free;
  end;
end;

end.
