# This script requires a Boolean variable to be configured in the Datto component config:
# - IgnoreInstalledVersionNumber (Uncommon) - Force an update regardless of installed agent version

# Where to download the AuthLite installer
$AuthliteServer = 'https://www.authlite.com/downloads/'

# RegEx to match the DisplayName of AuthLite in the registry when installed
$InstalledDisplayName = "^AuthLite [0-9\.]+$"

# Registry locations to check for existing installations
$x64RegistryLocation = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\'
$x86RegistryLocation = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

# Folder to save our downloads
$SavePath = "$($ENV:SystemDrive)\temp"

# Determine whether the Datto job is requesting the version number to be ignored
if ($env:IgnoreInstalledVersionNumber -eq $true) {$ForceUpdate = $true} else {$ForceUpdate = $false}

# Find the installed AuthLite version if present on this PC
try {
    $RegistryInstallObject = $null
    #Check for AuthLite in x64 registry location
    $RegistryInstallObject = Get-ItemProperty "$x64RegistryLocation*" | where-object -property displayname -Match $InstalledDisplayName
    if ($null -eq $RegistryInstallObject) {
        #Check for AuthLite in x86 registry location
        $RegistryInstallObject = Get-ItemProperty "$x86RegistryLocation*" | where-object -property displayname -Match $InstalledDisplayName
    }
} catch {
    Write-host 'There was a problem checking the registry for AuthLite.'
    write-host $_
}

# Isolate the version number installed if present
if ($null -ne $RegistryInstallObject) {
    [System.Version]$InstalledVersion = $RegistryInstallObject.displayversion
    Write-host "AuthLite v$InstalledVersion is already installed."
} else {
    Write-host 'AuthLite is not already installed.'
}

# Switch to TLS1.2 and grab the contents of the download page
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    $WebPageContent = Invoke-WebRequest $AuthliteServer -UseBasicParsing
} catch {
    Write-host 'There was a problem getting the latest available version of AuthLite.'
    Write-host 'Cannot continue downloading the installer.'
    write-host $_
    exit 1
}

# Find the first (newest) instance of the MSI installer
$LatestDownloadURL = $($($WebPageContent.links.href | `
    select-string -pattern "downloads/[0-9\.]+/AuthLite_installer_x64.msi")[0] | `
    Out-String).Trim()

# Isolate the latest version number
[System.Version]$LatestVersion = $($LatestDownloadURL.Substring($LatestDownloadURL.IndexOf("downloads/")+10).split("/")[0]).Trim()
write-host "The latest available version is $LatestVersion."

# Determine whether an update is needed
if (($null -ne $RegistryInstallObject) -and ($InstalledVersion -ge $LatestVersion) -and (-not $ForceUpdate)) {
    write-host "Installed version $InstalledVersion does not need an update."
}

# Proceed if installing new or if the engineer requested to ignore the installed version
if (($null -eq $RegistryInstallObject) -or ($ForceUpdate)) {
    # Create the save path if necessary and go there
    if ( -not (Test-Path -Path $SavePath)) {New-Item -ItemType Directory -Path $SavePath}
    Set-Location $SavePath

    if (($null -ne $RegistryInstallObject) -and ($ForceUpdate)) {Write-Host 'Job configured to ignore installed version.'}
    
    # Try to download the installer
    try {
        Write-host 'Downloading...'
        Invoke-WebRequest -URI $LatestDownloadURL -OutFile "$SavePath\AuthLite_installer_x64.msi"
    } catch {
        Write-host 'There was a problem downloading the installer.'
        write-host $_
        exit 1
    }
    
    # Try to run the installer
    try {
        Write-host 'Installing...'
        Start-Process msiexec -ArgumentList "/i AuthLite_installer_x64.msi /quiet /norestart" -Wait
        Write-host 'Done!'
    } catch {
        Write-host 'There was a problem installing AuthLite.'
        write-host $_
        exit 1
    }
}