param(
    [Parameter(Mandatory)]
    [string]$TargetPath
)

$LinkPath = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "Research Data File Share.lnk"
$Link = (New-Object -ComObject WScript.Shell).CreateShortcut($LinkPath)
$Link.TargetPath = $TargetPath

$Link.Save()
