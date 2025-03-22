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

# Function to check disk space
function Check-DiskSpace {
    param (
        [Parameter(Mandatory=$true)]
        [int]$MinimumFreePercentage
    )
    
    $drives = Get-PSDrive -PSProvider FileSystem
    foreach ($drive in $drives) {
        $freeSpace = $drive.Free
        $usedSpace = $drive.Used
        $totalSpace = $freeSpace + $usedSpace
        
        if ($totalSpace -gt 0) {
            $percentFree = [math]::Round(($freeSpace / $totalSpace) * 100, 2)
            
            if ($percentFree -lt $MinimumFreePercentage) {
                throw "Drive $($drive.Name): has only $percentFree% free space. Minimum required is $MinimumFreePercentage%."
                Exit 1
            }
        }
    }
    
    return $true
}

try {
    # Validate paths
    if (-not (Test-Path -Path $LocalPath)) {
        throw "Local path does not exist: $LocalPath"
    }

    if (-not (Test-Path -Path $OneDrivePath)) {
        throw "OneDrive path does not exist: $OneDrivePath"
    }

    # First, get all directories including the root
    $localDirs = @(Get-Item -LiteralPath $LocalPath)
    $localDirs += Get-ChildItem -Path $LocalPath -Directory -Recurse -Force
    
    $totalDirs = $localDirs.Count
    $currentDir = 0
    $totalProcessedFiles = 0
    
    foreach ($dir in $localDirs) {
        $currentDir++

        Check-DiskSpace -MinimumFreePercentage 20
        
        # Calculate relative path for the current directory
        $relativeDirPath = ""
        if ($dir.FullName -ne $LocalPath) {
            $relativeDirPath = $dir.FullName.Substring($LocalPath.Length)
            if ($relativeDirPath.StartsWith("\")) {
                $relativeDirPath = $relativeDirPath.Substring(1)
            }
        }
        
        $onedriveDirPath = Join-Path -Path $OneDrivePath -ChildPath $relativeDirPath
        
        # Ensure the directory exists in OneDrive
        if (-not (Test-Path -LiteralPath $onedriveDirPath)) {
            Write-Host "Creating directory in OneDrive: $relativeDirPath" -ForegroundColor Blue
            New-Item -Path $onedriveDirPath -ItemType Directory -Force | Out-Null
        }
        
        # Update directory progress
        Write-Progress -Id 1 -Activity "Processing directories" -Status "Directory $currentDir of $totalDirs" -PercentComplete (($currentDir / $totalDirs) * 100) -CurrentOperation $relativeDirPath
        
        # Get all files in the current directory (not recursive)
        $localFiles = Get-ChildItem -LiteralPath $dir.FullName -File -Force
        $totalFiles = $localFiles.Count
        $currentFile = 0
        
        foreach ($file in $localFiles) {
            $currentFile++
            $totalProcessedFiles++

            if ($currentFile % 20 -eq 0) {  # Only check every 20 files to avoid excessive checks
                Check-DiskSpace -MinimumFreePercentage 20
            }
            
            # For root directory files
            if ($dir.FullName -eq $LocalPath) {
                $relativeFilePath = $file.Name
            } else {
                # For files in subdirectories
                $relativeFilePath = Join-Path -Path $relativeDirPath -ChildPath $file.Name
            }
            
            # Construct the corresponding OneDrive path
            $onedriveFilePath = Join-Path -Path $OneDrivePath -ChildPath $relativeFilePath
            
            # Update file progress
            Write-Progress -Id 2 -ParentId 1 -Activity "Processing files in current directory" -Status "File $currentFile of $totalFiles" -PercentComplete (($currentFile / $totalFiles) * 100) -CurrentOperation $file.Name
            
            # Check if the file exists in OneDrive
            if (Test-Path -LiteralPath $onedriveFilePath) {
                # File exists in both locations, compare modification times and sizes
                $onedriveFile = Get-Item -LiteralPath $onedriveFilePath
                
                # Compare last write times
                if ($onedriveFile.LastWriteTime -gt $file.LastWriteTime) {
                    # OneDrive file is newer
                    Write-Host "OneDrive file is newer: $relativeFilePath - Deleting local file" -ForegroundColor Yellow
                    #Remove-Item -LiteralPath $file.FullName -Force
                }
                elseif ($onedriveFile.LastWriteTime -eq $file.LastWriteTime -and $onedriveFile.Length -eq $file.Length) {
                    # Files are identical (same modification time and size)
                    Write-Host "Files are identical: $relativeFilePath - Deleting local file" -ForegroundColor Green
                    #Remove-Item -LiteralPath $file.FullName -Force
                }
                else {
                    # Local file is newer
                    Write-Host "Local file is newer: $relativeFilePath - Moving to OneDrive (replacing)" -ForegroundColor Cyan
                    #Move-Item -LiteralPath $file.FullName -Destination $onedriveFilePath -Force
                }
            }
            else {
                # File doesn't exist in OneDrive, move it
                Write-Host "File doesn't exist in OneDrive: $relativeFilePath - Moving to OneDrive" -ForegroundColor Magenta
                #Move-Item -LiteralPath $file.FullName -Destination $onedriveFilePath
            }
        }
    }
    
    # Complete all progress bars
    Write-Progress -Id 1 -Activity "Processing directories" -Completed
    Write-Progress -Id 2 -Activity "Processing files" -Completed
    
    Write-Host "Synchronization complete. Processed $totalProcessedFiles files across $totalDirs directories." -ForegroundColor Green
} catch {
    Write-Progress -Activity "Synchronizing files" -Completed
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Script aborted at file $currentFile of $totalFiles." -ForegroundColor Red
    exit 1
}
