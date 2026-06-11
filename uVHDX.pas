unit uVHDX;

{
  Thin wrapper around the Windows Virtual Disk Service API (virtdisk.dll) for
  mounting / unmounting .vhdx (and .vhd) user-profile disks.

  Attaching a virtual disk requires the process to be running elevated
  (Administrator). The application manifest requests this.

  A disk attached without ATTACH_VIRTUAL_DISK_FLAG_PERMANENT_LIFETIME is
  automatically detached when the open handle is closed, so we keep the handle
  open for the lifetime of the mount and close it on Unmount.
}

interface

uses
  Winapi.Windows, System.SysUtils;

type
  TVirtualDisk = class
  private
    FFilePath: string;
    FHandle: THandle;
    FDriveLetter: Char;
    function NewDriveLetter(const ABeforeMask: DWORD): Char;
  public
    constructor Create(const AFilePath: string);
    destructor Destroy; override;

    { Opens and attaches the disk read/write, then waits for Windows to
      auto-mount the volume and assign a drive letter. Raises EOSError on
      failure (access denied, file in use, etc.). }
    procedure Mount;

    { Detaches the disk and closes the handle. Safe to call when not mounted. }
    procedure Unmount;

    property FilePath: string read FFilePath;
    property DriveLetter: Char read FDriveLetter;          // #0 when not mounted
    function IsMounted: Boolean;
    function DriveRoot: string;                            // e.g. 'F:\'
  end;

implementation

const
  virtdisk = 'virtdisk.dll';

  VIRTUAL_STORAGE_TYPE_DEVICE_VHD  = 2;
  VIRTUAL_STORAGE_TYPE_DEVICE_VHDX = 3;

  VIRTUAL_STORAGE_TYPE_VENDOR_MICROSOFT: TGUID =
    '{EC984AEC-A0F9-47E9-901F-71415A66345B}';

  VIRTUAL_DISK_ACCESS_ATTACH_RW = $00020000;
  VIRTUAL_DISK_ACCESS_DETACH    = $00040000;
  VIRTUAL_DISK_ACCESS_GET_INFO  = $00080000;

  OPEN_VIRTUAL_DISK_FLAG_NONE   = 0;
  ATTACH_VIRTUAL_DISK_FLAG_NONE = 0;
  DETACH_VIRTUAL_DISK_FLAG_NONE = 0;

  ATTACH_VIRTUAL_DISK_VERSION_1 = 1;

type
  VIRTUAL_STORAGE_TYPE = record
    DeviceId: ULONG;
    VendorId: TGUID;
  end;
  PVIRTUAL_STORAGE_TYPE = ^VIRTUAL_STORAGE_TYPE;

  ATTACH_VIRTUAL_DISK_PARAMETERS = record
    Version: DWORD;     // ATTACH_VIRTUAL_DISK_VERSION_1
    Reserved: ULONG;    // Version1.Reserved
  end;
  PATTACH_VIRTUAL_DISK_PARAMETERS = ^ATTACH_VIRTUAL_DISK_PARAMETERS;

function OpenVirtualDisk(VirtualStorageType: PVIRTUAL_STORAGE_TYPE;
  Path: PWideChar; VirtualDiskAccessMask: DWORD; Flags: DWORD;
  Parameters: Pointer; var Handle: THandle): DWORD; stdcall;
  external virtdisk name 'OpenVirtualDisk';

function AttachVirtualDisk(VirtualDiskHandle: THandle;
  SecurityDescriptor: PSECURITY_DESCRIPTOR; Flags: DWORD;
  ProviderSpecificFlags: ULONG; Parameters: PATTACH_VIRTUAL_DISK_PARAMETERS;
  Overlapped: POverlapped): DWORD; stdcall;
  external virtdisk name 'AttachVirtualDisk';

function DetachVirtualDisk(VirtualDiskHandle: THandle; Flags: DWORD;
  ProviderSpecificFlags: ULONG): DWORD; stdcall;
  external virtdisk name 'DetachVirtualDisk';

{ TVirtualDisk }

constructor TVirtualDisk.Create(const AFilePath: string);
begin
  inherited Create;
  FFilePath := AFilePath;
  FHandle := INVALID_HANDLE_VALUE;
  FDriveLetter := #0;
end;

destructor TVirtualDisk.Destroy;
begin
  Unmount;
  inherited;
end;

function TVirtualDisk.IsMounted: Boolean;
begin
  Result := (FHandle <> INVALID_HANDLE_VALUE) and (FDriveLetter <> #0);
end;

function TVirtualDisk.DriveRoot: string;
begin
  if FDriveLetter <> #0 then
    Result := FDriveLetter + ':\'
  else
    Result := '';
end;

function TVirtualDisk.NewDriveLetter(const ABeforeMask: DWORD): Char;
var
  AfterMask: DWORD;
  i, Tries: Integer;
begin
  Result := #0;
  // Auto-mount can lag slightly behind the attach call; poll for a new bit.
  for Tries := 0 to 24 do
  begin
    AfterMask := GetLogicalDrives;
    for i := 0 to 25 do
      if ((AfterMask and (DWORD(1) shl i)) <> 0) and
         ((ABeforeMask and (DWORD(1) shl i)) = 0) then
        Exit(Char(Ord('A') + i));
    Sleep(200);
  end;
end;

procedure TVirtualDisk.Mount;
var
  StorageType: VIRTUAL_STORAGE_TYPE;
  AttachParams: ATTACH_VIRTUAL_DISK_PARAMETERS;
  BeforeMask: DWORD;
  Res: DWORD;
begin
  if IsMounted then
    Exit;

  FillChar(StorageType, SizeOf(StorageType), 0);
  if SameText(ExtractFileExt(FFilePath), '.vhd') then
    StorageType.DeviceId := VIRTUAL_STORAGE_TYPE_DEVICE_VHD
  else
    StorageType.DeviceId := VIRTUAL_STORAGE_TYPE_DEVICE_VHDX;
  StorageType.VendorId := VIRTUAL_STORAGE_TYPE_VENDOR_MICROSOFT;

  Res := OpenVirtualDisk(@StorageType, PWideChar(FFilePath),
    VIRTUAL_DISK_ACCESS_ATTACH_RW or VIRTUAL_DISK_ACCESS_DETACH or
    VIRTUAL_DISK_ACCESS_GET_INFO, OPEN_VIRTUAL_DISK_FLAG_NONE, nil, FHandle);
  if Res <> ERROR_SUCCESS then
  begin
    FHandle := INVALID_HANDLE_VALUE;
    raise EOSError.Create('Could not open virtual disk:'#13#10 +
      SysErrorMessage(Res));
  end;

  FillChar(AttachParams, SizeOf(AttachParams), 0);
  AttachParams.Version := ATTACH_VIRTUAL_DISK_VERSION_1;

  BeforeMask := GetLogicalDrives;

  Res := AttachVirtualDisk(FHandle, nil, ATTACH_VIRTUAL_DISK_FLAG_NONE, 0,
    @AttachParams, nil);
  if Res <> ERROR_SUCCESS then
  begin
    CloseHandle(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
    raise EOSError.Create('Could not attach virtual disk:'#13#10 +
      SysErrorMessage(Res));
  end;

  FDriveLetter := NewDriveLetter(BeforeMask);
  if FDriveLetter = #0 then
    // Attached but no drive letter surfaced (e.g. partition has no mount point).
    raise EOSError.Create('The disk was attached but Windows did not assign a '
      + 'drive letter to its volume. It may need a drive letter assigned in '
      + 'Disk Management.');
end;

procedure TVirtualDisk.Unmount;
begin
  if FHandle <> INVALID_HANDLE_VALUE then
  begin
    DetachVirtualDisk(FHandle, DETACH_VIRTUAL_DISK_FLAG_NONE, 0);
    CloseHandle(FHandle);
    FHandle := INVALID_HANDLE_VALUE;
  end;
  FDriveLetter := #0;
end;

end.
