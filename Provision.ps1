<#
.SYNOPSIS
This script provisions a Windows machine for a user by:
- Ensuring the user is signed into Microsoft 365 (Graph) if not already.
- Configures and logs into OneDrive.
- Enables Known Folder Move (KFM) to back up Desktop, Documents, Pictures, etc.
- Syncs a Group (SharePoint) folder to the user's OneDrive.
- Ensures the M365 account is added to all Office apps.

Note: Some steps may still require user interaction (e.g., initial auth prompts).
#>

# Execute Set-ExecutionPolicy Bypass -Scope Process

$TenantName = "disfault"

# Requires Microsoft.Graph module
try {
    Import-Module Microsoft.Graph.Users -ErrorAction Stop
} catch {
    Write-Host "Microsoft Graph module not found. Installing..."
    Install-Module Microsoft.Graph -Scope CurrentUser -Force
    Import-Module Microsoft.Graph.Users
}
Import-Module Microsoft.Graph.Groups

# Connect to Microsoft Graph to ensure user is signed in
$tokenStatus = $null
try {
    # Attempt a command that would require a token. If token exists, no prompt.
    Get-MgUser -Top 1 -ErrorAction Stop | Out-Null
    Write-Host "User is already signed into Microsoft 365."
    $tokenStatus = "AlreadySignedIn"
} catch {
    Write-Host "User not signed in. Prompting for Microsoft 365 login..."
    Connect-MgGraph -Scopes "User.Read Files.ReadWrite" -ErrorAction Stop -NoWelcome
    Get-MgUser -Top 1 -ErrorAction Stop | Out-Null
    Write-Host "User successfully signed into Microsoft 365."
    $tokenStatus = "NewlySignedIn"
}

# Determine the user's UPN (Primary email)
$context = Get-MgContext
$userUPN = $context.Account
$tenantID = $context.TenantId
Write-Host "User Principal Name (UPN): $userUPN"

# ------------------------------------------------------------------------
# Configure OneDrive
# ------------------------------------------------------------------------
# Path to OneDrive client
$OneDriveExe = "$($env:LocalAppData)\Microsoft\OneDrive\OneDrive.exe"
if (-Not (Test-Path $OneDriveExe)) {
    Write-Host "OneDrive client not found, downloading..."
    $OneDriveSetup = "$env:TEMP\OneDriveSetup.exe"
    Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=844652" -OutFile $OneDriveSetup # From ChatGPT
    #Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/?linkid=2182910" -OutFile $OneDriveSetup # From Google
    Write-Host "Installing OneDrive..."
    Start-Process $OneDriveSetup -ArgumentList "/silent" -Wait
    # After installation, update $OneDriveExe if needed
    $OneDriveExe = "$($env:LocalAppData)\Microsoft\OneDrive\OneDrive.exe"
}


# Before launching OneDrive, check if it's already configured:
$OneDriveAccountKey = "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1"
$OneDriveConfigured = $false
if (Test-Path $OneDriveAccountKey) {
    $cfgTenantId = (Get-ItemProperty $OneDriveAccountKey).ConfiguredTenantId
    $cfgStatus = (Get-ItemProperty $OneDriveAccountKey).GetOnlineStatus
    if (($cfgTenantId -eq $tenantID) -and ($cfgStatus -eq "Completed")) {
        Write-Host "OneDrive is already configured and signed in. Skipping auto-configure."
        $OneDriveConfigured = $true
    }
}

if (-not $OneDriveConfigured) {
    Write-Host "Attempting silent OneDrive configuration..."
    # Restart OneDrive
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Process $OneDriveExe

    $maxWaitSeconds = 300
    $interval = 5
    $elapsed = 0
    $connected = $false

    Write-Host "Waiting for OneDrive to complete sign-in..."
    while ($elapsed -lt $maxWaitSeconds) {
        Start-Sleep -Seconds $interval
        $elapsed += $interval
        if ((Test-Path $OneDriveAccountKey) -and ($cfgTenantId -eq $tenantID) -and ($cfgStatus -eq "Completed")) {
            Write-Host "OneDrive is now connected!"
            $connected = $true
        }
    }

    if (-not $connected) {
        Write-Host "Timed out waiting for OneDrive to connect."
        Exit 1
    }

    if (Test-Path $OneDriveAccountKey -and $cfgStatus -eq "Completed") {
        Write-Host "OneDrive has been silently configured."
    } else {
        Write-Host "Silent OneDrive configuration failed. The user may be prompted to sign in."
        Exit 1
    }
}

# ------------------------------------------------------------------------
# Add a Group (SharePoint) Folder to Explorer via OneDrive Sync
# ------------------------------------------------------------------------
# To sync a SharePoint library (e.g., from a Microsoft 365 Group), use OneDrive client.
try {
    Import-Module AzureAD -ErrorAction Stop
} catch {
    Write-Host "Microsoft Graph module not found. Installing..."
    Install-Module AzureAD -Scope CurrentUser -Force
    Import-Module AzureAD
}

Connect-AzureAD

$userAD = Get-AzureADUser -ObjectId $userUPN
$JoinedGroups = Get-AzureADUserMembership -ObjectId $userAD.ObjectId | Where-Object -Property DisplayName -ne "Disfault"
if ($JoinedGroups.Count -eq 1) {
    $GroupName = $JoinedGroups.MailNickName
    Write-Host "User is in one group: $GroupName"
} else {
    $JoinedGroupsList = (echo $JoinedGroups | select -Property DisplayName -ExpandProperty DisplayName) -join ", "
    Write-Error "User is not in exactly one group. Found $($JoinedGroups.Count) groups: $JoinedGroupsList"
    exit 1
}

# Replace the tenant placeholder in the SharePoint URL usage:
$GroupLibraryUrl = "https://$TenantName.sharepoint.com/sites/$GroupName/Shared%20Documents"

# Needs more data to work
#$odopenURL = "odopen://sync?userId=$($userAD.ObjectId)&userEmail=$userUPN&isSiteAdmin=0&site=$([URI]::EscapeUriString($userAD.ObjectId))"
Write-Host "Navigating to $GroupLibraryUrl"
[System.Windows.MessageBox]::Show("Please sync the group folder from the opened Edge window and 'add a shortcut to onedrive'")
#MicrosoftEdge.exe $GroupLibraryUrl
Start-Process microsoft-edge:$GroupLibraryUrl

Write-Host "Provisioning steps completed. Please verify OneDrive sync and Office account sign-in."
