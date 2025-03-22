# This script was used for Gogo to implement a kind of 2 way sync to the group OneDrive
# The group folder files already existed on the local machine and they have changes so they're out of sync with the group
# It iterates over all the files pointed by localpath and makes sure that the onedrivepath has all the files
# and if the local file is newer, it overwrites it on the group
# it also REMOVES the local files as it goes
#
# it removes it for good, no trash/recycle bin, take care

#param (
#    [Parameter(Mandatory=$true)]
#    [string]$LocalPath,
    
#    [Parameter(Mandatory=$true)]
#    [string]$OneDrivePath
#)
$LocalPath = "D:\Users\User02\OneDrive - DIMOS AGIAS"
$OneDrivePath = "D:\OneDrive Grafeio Dim\OneDrive - Δήμος Αγιάς Cloud\Έγγραφα - Γραφείο Δημάρχου"

$ErrorActionPreference = "Stop"
try {

# Validate paths
if (-not (Test-Path -LiteralPath $LocalPath)) {
    Write-Error "Local path does not exist: $LocalPath"
    exit 1
}

if (-not (Test-Path -LiteralPath $OneDrivePath)) {
    Write-Error "OneDrive path does not exist: $OneDrivePath"
    exit 1
}

# Get all files from local path
$localFiles = Get-ChildItem -LiteralPath $LocalPath -File -Recurse

$totalFiles = $localFiles.Count
$currentFile = 0

foreach ($file in $localFiles) {
    $currentFile++
    
    # Calculate relative path
    $relativePath = $file.FullName.Substring($LocalPath.Length)
    if ($relativePath.StartsWith("\")) {
        $relativePath = $relativePath.Substring(1)
    }
    
    # Construct the corresponding OneDrive path
    $onedriveFilePath = Join-Path -Path $OneDrivePath -ChildPath $relativePath
    $onedriveFileDir = Split-Path -Path $onedriveFilePath -Parent
    
    # Update progress bar
    $percentComplete = ($currentFile / $totalFiles) * 100
    Write-Progress -Activity "Synchronizing files" -Status "Processing file $currentFile of $totalFiles" -PercentComplete $percentComplete -CurrentOperation $relativePath
    
    # Check if the file exists in OneDrive
    if (Test-Path -LiteralPath $onedriveFilePath) {
        # File exists in both locations, compare modification times and sizes
        $onedriveFile = Get-Item -LiteralPath $onedriveFilePath
        
        # Compare last write times
        if ($onedriveFile.LastWriteTime -gt $file.LastWriteTime) {
            # OneDrive file is newer
            Write-Host "OneDrive file is newer: $relativePath - Deleting local file" -ForegroundColor Yellow
            #Remove-Item -LiteralPath $file.FullName -Force
        }
        elseif ($onedriveFile.LastWriteTime -eq $file.LastWriteTime -and $onedriveFile.Length -eq $file.Length) {
            # Files are identical (same modification time and size)
            Write-Host "Files are identical: $relativePath - Deleting local file" -ForegroundColor Green
            #Remove-Item -LiteralPath $file.FullName -Force
        }
        else {
            # Local file is newer
            Write-Host "Local file is newer: $relativePath - Moving to OneDrive (replacing)" -ForegroundColor Cyan
            #Move-Item -LiteralPath $file.FullName -Destination $onedriveFilePath -Force
        }
    }
    else {
        # File doesn't exist in OneDrive, move it
        # Ensure the destination directory exists
        if (-not (Test-Path -LiteralPath $onedriveFileDir)) {
            New-Item -Path $onedriveFileDir -ItemType Directory -Force | Out-Null
        }
        
        Write-Host "File doesn't exist in OneDrive: $relativePath - Moving to OneDrive" -ForegroundColor Magenta
        #Move-Item -LiteralPath $file.FullName -Destination $onedriveFilePath
    }
}

Write-Progress -Activity "Synchronizing files" -Completed
Write-Host "Synchronization complete. Processed $totalFiles files." -ForegroundColor Green
} catch {
    Write-Progress -Activity "Synchronizing files" -Completed
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script aborted at file $currentFile of $totalFiles." -ForegroundColor Red
    exit 1
}
