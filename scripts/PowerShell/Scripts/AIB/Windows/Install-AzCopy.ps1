function Write-Log {
    param (
        $Message
    )

    $FormattedTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "$FormattedTime Install-AzCopy: $Message"
}

$BuildDirectory = $env:TEMP

$InstallerFilename = "azcopy.zip"
$DownloadUrl = "https://aka.ms/downloadazcopy-v10-windows"

Write-Log "Downloading azcopy zip file"
Invoke-WebRequest $DownloadUrl -OutFile $BuildDirectory\$InstallerFilename

Write-Log "Extracting azcopy to C:\"
Expand-Archive -Path "$BuildDirectory\$InstallerFilename" -DestinationPath C:\

Write-Log "azcopy script completed"