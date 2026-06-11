unit uShellUtils;

{
  File-system / shell helpers used to fill the VirtualTreeView controls:
    - the Windows system small-icon image list (for real shell icons),
    - per-file icon index + type name via SHGetFileInfo,
    - directory enumeration (folders first, then files).

  Nothing here depends on VirtualTrees, so it can be unit-tested in isolation.
}

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, Vcl.Controls,
  System.Generics.Collections;

type
  TFileEntry = record
    DisplayName: string;
    FullPath: string;
    IsDir: Boolean;
    Size: Int64;
    Modified: TDateTime;
    IconIndex: Integer;
    TypeName: string;
  end;

{ Creates a TImageList that shares the Windows system small-icon image list.
  ShareImages is set so freeing the TImageList will not destroy the system list. }
function CreateSystemImageList(AOwner: TComponent): TImageList;

{ Resolves the small-icon index (into the system image list) and the friendly
  type name for a file/folder name, using attributes only (no disk access). }
procedure GetShellInfo(const AName: string; AIsDir: Boolean;
  out AIconIndex: Integer; out ATypeName: string);

{ Returns the entries directly inside ADir, folders first then files (each group
  sorted by name). When AIncludeFiles is False only sub-folders are returned. }
function ListFolder(const ADir: string; AIncludeFiles: Boolean): TArray<TFileEntry>;

{ True if ADir contains at least one sub-folder (used to decide whether a tree
  node should show an expand button). }
function HasSubfolders(const ADir: string): Boolean;

implementation

uses
  Winapi.ShellAPI, System.Generics.Defaults, System.IOUtils;

function CreateSystemImageList(AOwner: TComponent): TImageList;
var
  Sfi: TSHFileInfo;
  H: THandle;
begin
  Result := TImageList.Create(AOwner);
  Result.ShareImages := True;          // do not free the shared system list
  FillChar(Sfi, SizeOf(Sfi), 0);
  H := THandle(SHGetFileInfo('C:\', 0, Sfi, SizeOf(Sfi),
    SHGFI_SYSICONINDEX or SHGFI_SMALLICON));
  if H <> 0 then
    Result.Handle := H;
end;

procedure GetShellInfo(const AName: string; AIsDir: Boolean;
  out AIconIndex: Integer; out ATypeName: string);
var
  Sfi: TSHFileInfo;
  Attr: DWORD;
begin
  if AIsDir then
    Attr := FILE_ATTRIBUTE_DIRECTORY
  else
    Attr := FILE_ATTRIBUTE_NORMAL;
  FillChar(Sfi, SizeOf(Sfi), 0);
  SHGetFileInfo(PChar(AName), Attr, Sfi, SizeOf(Sfi),
    SHGFI_USEFILEATTRIBUTES or SHGFI_SYSICONINDEX or SHGFI_SMALLICON or
    SHGFI_TYPENAME);
  AIconIndex := Sfi.iIcon;
  ATypeName := Sfi.szTypeName;
end;

function HasSubfolders(const ADir: string): Boolean;
var
  Sr: TSearchRec;
begin
  Result := False;
  if FindFirst(IncludeTrailingPathDelimiter(ADir) + '*', faDirectory, Sr) = 0 then
  try
    repeat
      if ((Sr.Attr and faDirectory) <> 0) and (Sr.Name <> '.') and
         (Sr.Name <> '..') then
        Exit(True);
    until FindNext(Sr) <> 0;
  finally
    FindClose(Sr);
  end;
end;

function ListFolder(const ADir: string; AIncludeFiles: Boolean): TArray<TFileEntry>;
var
  Sr: TSearchRec;
  List: TList<TFileEntry>;
  E: TFileEntry;
  IsDir: Boolean;
  Base: string;
begin
  List := TList<TFileEntry>.Create;
  try
    Base := IncludeTrailingPathDelimiter(ADir);
    if FindFirst(Base + '*', faAnyFile, Sr) = 0 then
    try
      repeat
        if (Sr.Name = '.') or (Sr.Name = '..') then
          Continue;
        IsDir := (Sr.Attr and faDirectory) <> 0;
        if (not IsDir) and (not AIncludeFiles) then
          Continue;
        E.DisplayName := Sr.Name;
        E.FullPath := Base + Sr.Name;
        E.IsDir := IsDir;
        if IsDir then
          E.Size := 0
        else
          E.Size := Sr.Size;
        E.Modified := Sr.TimeStamp;
        GetShellInfo(Sr.Name, IsDir, E.IconIndex, E.TypeName);
        List.Add(E);
      until FindNext(Sr) <> 0;
    finally
      FindClose(Sr);
    end;

    // Folders first, then files; each group alphabetical (case-insensitive).
    List.Sort(TComparer<TFileEntry>.Construct(
      function(const A, B: TFileEntry): Integer
      begin
        if A.IsDir <> B.IsDir then
        begin
          if A.IsDir then Result := -1 else Result := 1;
        end
        else
          Result := AnsiCompareText(A.DisplayName, B.DisplayName);
      end));

    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
