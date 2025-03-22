# Get all files recursively
$folders = Get-ChildItem -Path "D:\YourPath" -Directory -Recurse


Write-Host "Found $($folders.Count) files"

# Create hashtable to store original files by name (without "- Αντιγραφή")
$originalFiles = @{}

# Function to calculate MD5 hash of a file
function Get-FileHash($filePath) {
    $md5 = [System.Security.Cryptography.MD5]::Create()
    $stream = [System.IO.File]::OpenRead($filePath)
    try {
        $hashBytes = $md5.ComputeHash($stream)
        return [System.BitConverter]::ToString($hashBytes).Replace("-", "")
    }
    finally {
        $stream.Close()
        $md5.Dispose()
    }
}

# Process each folder
$folderCount = $folders.Count
$currentFolderIndex = 0

foreach ($folder in $folders) {
    $currentFolderIndex++
    Write-Progress -Id 0 -Activity "Processing Folders" -Status "Folder: $($folder.FullName)" `
                  -PercentComplete (($currentFolderIndex / $folderCount) * 100)
    
    Write-Host "`nProcessing folder: $($folder.FullName)" -ForegroundColor Cyan
    Write-Host "`nFound folder: $($folder.FullName)" -ForegroundColor Cyan
    $confirmation = Read-Host "Process this folder? (yes/no/quit)"
            
    if ($confirmation -eq 'quit') {
        Write-Host "`nExiting script..." -ForegroundColor Yellow
        break
    }
    if ($confirmation -ne 'yes') {
        Write-Host "Skipping folder..." -ForegroundColor Yellow
        continue
    }
    
    # Get files in current folder (non-recursive)
    $files = Get-ChildItem -Path $folder.FullName -File -Recurse
    $fileCount = $files.Count
    $currentFileIndex = 0

    # Process each file in the folder
    foreach ($file in $files) {
        $currentFileIndex++
        Write-Progress -Id 1 -Activity "Processing Files" -Status "File: $($file.Name)" `
                      -PercentComplete (($currentFileIndex / $fileCount) * 100) `
                      -ParentId 0

        $baseName = $file.Name
        
        # If file has "- Αντιγραφή" in name
        if ($baseName -match "- Αντιγραφή") {

            # Get the original file name by removing "- Αντιγραφή"
            $originalName = $baseName -replace " - Αντιγραφή", ""
            $originalPath = Join-Path $file.Directory.FullName $originalName
            
            # If original file exists
            if (Test-Path $originalPath) {
                $shouldProcess = $false
                # Compare file sizes first
                if ($file.Length -eq (Get-Item $originalPath).Length) {
                    Write-Host "File sizes are equal"
                    $copyHash = Get-FileHash $file.FullName
                    $origHash = Get-FileHash $originalPath
                    
                    Write-Host "`nComparing files:"
                    Write-Host "Original (to be deleted): $originalPath"
                    Write-Host "Copy (to keep): $($file.FullName)"
                    
                    if ($copyHash -eq $origHash) {
                        Write-Host "Files are identical" -ForegroundColor Green
                        $shouldProcess = $true
                    } else {
                        Write-Host "Files are different - manual review needed" -ForegroundColor Red
                    }
                } else {
                    Write-Host "`nFiles have different sizes - manual review needed:"
                    Write-Host "Original: $originalPath"
                    Write-Host "Copy: $($file.FullName)" -ForegroundColor Red
                }

                if ($shouldProcess) {
                    # Delete original file first to free up the name
                    Remove-Item $originalPath -Force
                    Write-Host "Deleted: $originalPath" -ForegroundColor Yellow
                    
                    # Rename the copy to the original name
                    Rename-Item -Path $file.FullName -NewName $originalName
                    Write-Host "Renamed: $($file.FullName) -> $originalPath" -ForegroundColor Green
                }
            }
        }
    }
}

# Clear the progress bars
Write-Progress -Id 0 -Activity "Processing Folders" -Completed
Write-Progress -Id 1 -Activity "Processing Files" -Completed
