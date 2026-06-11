object frmExplorer: TfrmExplorer
  Left = 0
  Top = 0
  Caption = 'Profile Disk'
  ClientHeight = 561
  ClientWidth = 884
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poMainFormCenter
  ShowHint = True
  OnCreate = FormCreate
  TextHeight = 15
  object splMain: TSplitter
    Left = 281
    Top = 49
    Height = 463
    ExplicitLeft = 200
    ExplicitTop = 120
    ExplicitHeight = 100
  end
  object pnlTop: TPanel
    Left = 0
    Top = 0
    Width = 884
    Height = 49
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblHeader: TLabel
      AlignWithMargins = True
      Left = 12
      Top = 3
      Width = 869
      Height = 43
      Margins.Left = 12
      Align = alClient
      Caption = 'Profile disk'
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -16
      Font.Name = 'Segoe UI'
      Font.Style = [fsBold]
      ParentFont = False
      Layout = tlCenter
      ExplicitWidth = 86
      ExplicitHeight = 21
    end
  end
  object pnlBottom: TPanel
    Left = 0
    Top = 512
    Width = 884
    Height = 49
    Align = alBottom
    BevelOuter = bvNone
    TabOrder = 1
    object btnUnmount: TButton
      AlignWithMargins = True
      Left = 681
      Top = 8
      Width = 95
      Height = 33
      Hint = 'Detach the virtual disk and close this view'
      Margins.Top = 8
      Margins.Bottom = 8
      Align = alRight
      Caption = 'Unmount'
      ModalResult = 1
      TabOrder = 0
      OnClick = btnUnmountClick
    end
    object btnDelete: TButton
      AlignWithMargins = True
      Left = 782
      Top = 8
      Width = 95
      Height = 33
      Hint = 'Unmount, then permanently delete the profile disk file'
      Margins.Top = 8
      Margins.Right = 7
      Margins.Bottom = 8
      Align = alRight
      Caption = 'Delete...'
      TabOrder = 1
      OnClick = btnDeleteClick
    end
  end
  object vstTree: TVirtualStringTree
    Left = 0
    Top = 49
    Width = 281
    Height = 463
    Align = alLeft
    Header.AutoSizeIndex = 0
    Header.Options = [hoColumnResize, hoVisible]
    TabOrder = 2
    TreeOptions.PaintOptions = [toShowButtons, toShowDropmark, toShowRoot, toShowTreeLines, toThemeAware, toUseBlendedImages]
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnExpanding = vstTreeExpanding
    OnFocusChanged = vstTreeFocusChanged
    OnFreeNode = vstTreeFreeNode
    OnGetText = vstTreeGetText
    OnGetImageIndex = vstTreeGetImageIndex
    Touch.InteractiveGestures = [igPan, igPressAndTap]
    Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
    Columns = <
      item
        Position = 0
        Text = 'Folders'
        Width = 281
      end>
  end
  object vstFiles: TVirtualStringTree
    Left = 284
    Top = 49
    Width = 600
    Height = 463
    Align = alClient
    Header.AutoSizeIndex = 0
    Header.Options = [hoColumnResize, hoShowSortGlyphs, hoVisible, hoHeaderClickAutoSort]
    TabOrder = 3
    TreeOptions.PaintOptions = [toShowDropmark, toShowHorzGridLines, toThemeAware, toUseBlendedImages]
    TreeOptions.SelectionOptions = [toFullRowSelect]
    OnCompareNodes = vstFilesCompareNodes
    OnDblClick = vstFilesDblClick
    OnFreeNode = vstFilesFreeNode
    OnGetText = vstFilesGetText
    OnGetImageIndex = vstFilesGetImageIndex
    Touch.InteractiveGestures = [igPan, igPressAndTap]
    Touch.InteractiveGestureOptions = [igoPanSingleFingerHorizontal, igoPanSingleFingerVertical, igoPanInertia, igoPanGutter, igoParentPassthrough]
    Columns = <
      item
        Position = 0
        Text = 'Name'
        Width = 280
      end
      item
        Position = 1
        Text = 'Type'
        Width = 160
      end
      item
        Alignment = taRightJustify
        Position = 2
        Text = 'Size'
        Width = 100
      end
      item
        Position = 3
        Text = 'Date Modified'
        Width = 150
      end>
  end
end
