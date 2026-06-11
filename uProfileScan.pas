unit uProfileScan;

{
  Scans a folder for user-profile virtual disks (*.vhdx / *.vhd) and resolves
  each file to a user account.

  Remote Desktop Services User Profile Disks are named  UVHD-<SID>.vhdx  where
  <SID> is the string form of the account's security identifier
  (e.g. UVHD-S-1-5-21-1111111111-2222222222-3333333333-1601.vhdx). We strip the
  UVHD- prefix, convert the SID back to an account name via LookupAccountSid and
  display it. Files that are not SID-named fall back to the bare file name, and
  the RDS template disk (UVHD-template) is labelled as such.
}

interface

uses
  System.SysUtils, System.Classes, System.Generics.Collections;

type
  TProfileItem = class
  public
    FileName: string;      // name only, e.g. UVHD-S-1-5-...-1601.vhdx
    FullPath: string;      // full path on disk
    UserName: string;      // resolved account, or fallback text
    SizeBytes: Int64;
    LastAccess: TDateTime;
  end;

  TProfileList = TObjectList<TProfileItem>;

{ Returns an owning list of profile items found directly in AFolder.
  Caller owns the result and must free it. }
function ScanFolder(const AFolder: string): TProfileList;

{ Resolves a profile disk file name (with or without extension) to a friendly
  user name. Exposed for reuse / testing. }
function ResolveProfileUser(const AFileName: string): string;

implementation

uses
  Winapi.Windows, System.IOUtils, System.Masks;

const
  UPD_PREFIX = 'UVHD-';

function ConvertStringSidToSidW(StringSid: PWideChar;
  var Sid: PSID): BOOL; stdcall; external 'advapi32.dll';

function SidToAccountName(Sid: PSID; out AName: string): Boolean;
var
  Name, Domain: array[0..255] of Char;
  cchName, cchDomain: DWORD;
  Use: SID_NAME_USE;
begin
  cchName := Length(Name);
  cchDomain := Length(Domain);
  Result := LookupAccountSid(nil, Sid, Name, cchName, Domain, cchDomain, Use);
  if Result then
  begin
    if Domain[0] <> #0 then
      AName := string(Domain) + '\' + string(Name)
    else
      AName := string(Name);
  end;
end;

function ResolveProfileUser(const AFileName: string): string;
var
  Base, SidStr: string;
  Sid: PSID;
  Resolved: string;
begin
  Base := TPath.GetFileNameWithoutExtension(AFileName);

  // RDS template disk - not tied to any user.
  if SameText(Base, UPD_PREFIX + 'template') then
    Exit('(template)');

  if Base.StartsWith(UPD_PREFIX, True) then
    SidStr := Base.Substring(Length(UPD_PREFIX))
  else
    SidStr := Base;

  Sid := nil;
  if ConvertStringSidToSidW(PWideChar(SidStr), Sid) then
  try
    if SidToAccountName(Sid, Resolved) then
      Exit(Resolved);
  finally
    LocalFree(HLOCAL(Sid));
  end;

  // Not a resolvable SID - show the raw base name as a best effort.
  Result := Base;
end;

function ScanFolder(const AFolder: string): TProfileList;

  procedure Collect(const APattern: string);
  var
    Path: string;
    Item: TProfileItem;
  begin
    for Path in TDirectory.GetFiles(AFolder, APattern,
      TSearchOption.soTopDirectoryOnly) do
    begin
      Item := TProfileItem.Create;
      try
        Item.FullPath := Path;
        Item.FileName := TPath.GetFileName(Path);
        Item.UserName := ResolveProfileUser(Item.FileName);
        Item.SizeBytes := TFile.GetSize(Path);
        Item.LastAccess := TFile.GetLastAccessTime(Path);
      except
        Item.Free;
        raise;
      end;
      Result.Add(Item);
    end;
  end;

begin
  Result := TProfileList.Create(True { OwnsObjects });
  try
    if not TDirectory.Exists(AFolder) then
      Exit;
    Collect('*.vhdx');
    Collect('*.vhd');
  except
    Result.Free;
    raise;
  end;
end;

end.
