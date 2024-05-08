function Write-Log {
    param (
        [string]$Message
    )

    $FormattedTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Write-Host "$FormattedTime Install-StorageExplorer: $Message"
}

$BuildDirectory = $env:Temp

Set-Location -Path $BuildDirectory

# Azure Storage Explorer
$InstallerFilename = "StorageExplorer.exe"
$DownloadUrl = "https://go.microsoft.com/fwlink/?LinkId=708343&clcid=0x809"
$InstallerArguments = "/VERYSILENT /NORESTART /ALLUSERS"

Write-Log "Downloading Azure Storage Explorer installer"
Invoke-WebRequest -Uri $DownloadUrl -UseBasicParsing -OutFile "$BuildDirectory\$InstallerFilename"

Write-Log "Installing Azure Storage Explorer"
Start-Process $InstallerFilename -ArgumentList $InstallerArguments -Wait

Write-Log "Storage Explorer script completed"