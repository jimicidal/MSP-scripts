#This script requires a Boolean input variable in Datto RMM: RebootOnSuccess

#Registry locations to check for existing VPN/other software installations
$RegistryInstallLocations = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\',
    'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'
)

#DisplayName of the VPN client in the registry when it's installed
$InstalledDisplayName = 'FortiClient'

#FCConfig.exe expected location on disk - used for backup/restore of VPN settings
$FCCPath = "$ENV:SystemDrive\Program Files\Fortinet\FortiClient\FCConfig.exe"

#The custom temp folder and file name(s) we'll be working with
$SavePath = "$ENV:SystemDrive\temp"
$OnlineInstallerName = 'FortiClientVPNOnlineInstaller.exe'
$SettingsBackupFilename = 'FCTSettingsEnc.xml'

#The URL to download the online installer. This was found at fortinet.com by going to
#the FortiClient download page and using the 'inspect element' and 'developer tools'
#browser features during a manual download
$OnlineInstallerURL = "https://filestore.fortinet.com/forticlient/$OnlineInstallerName"

#The FortiClient online installer's temp dir and related files
#These are located in user's %localappdata%\temp instead when not running as SYSTEM
$InstallerDir = "$Env:windir\temp"
#$InstallerDir = "$Env:SystemDrive\Users\<user>\AppData\Local\Temp" #(local testing only)
$InstallerLog = "$InstallerDir\fctinstall.log"
$OfflineInstallerName = 'FortiClientVPN.exe'


#Begin by checking the registry for an existing installation of the VPN client
try {
    $RegistryInstallObject = (Get-ChildItem $RegistryInstallLocations | get-itemproperty | where-object -property displayname -Match $InstalledDisplayName)
} catch {
    Write-host 'There was a problem checking the registry for existing VPN installations.'
    write-host $_
}

#Check for existing VPN connection(s)
$ActiveVPNConnections = get-netipconfiguration | Where-Object {($_.interfacedescription -match 'Fortinet SSL VPN') -and ($_.NetAdapter.Status -ne 'Disconnected')}
if ($ActiveVPNConnections) {
    Write-host 'Active VPN connection detected - opting not to proceed with update.'
    exit 1
} else {
    write-host 'No active VPN connections detected, OK to proceed.'
}

#Start update procedure if the app is found in the registry
if ($null -ne $RegistryInstallObject) {
    $InstalledVersion = $RegistryInstallObject.DisplayVersion
    Write-Host "$InstalledDisplayName $InstalledVersion is installed."
} else {
    Write-Host "$InstalledDisplayName is not currently installed."
}

#Quit if FCConfig.exe is not found - unless we're installing fresh
if ((-not (test-path $FCCPath)) -and ($null -ne $RegistryInstallObject)) {
    Write-host 'FCConfig.exe was not found - this is needed to preserve the VPN configuration.'
    exit 1
}

#Create the temp folder if it doesn't already exist
if ( -not (Test-Path -Path $SavePath)) {New-Item -ItemType Directory -Path $SavePath | out-null}

#Back up config if we're updating an existing install
if ($null -ne $RegistryInstallObject) {
    #Generate a random password to encrypt the exported settings file
    $randomBytes = New-Object byte[] 32
    $rngObject = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    $rngObject.GetBytes($randomBytes)
    $exportPassword = [System.Convert]::ToBase64String($randomBytes)

    #Try to export the config using FCConfig.exe
    try {
        start-process "$FCCPath" -WindowStyle Hidden -argumentlist "-m all -f $SavePath\$SettingsBackupFilename -o export -q -i 1 -p $exportPassword" -wait
        write-host "Settings backed up to $SavePath\$SettingsBackupFilename."
    } catch {
        write-host 'There was a problem backing up the existing VPN client settings.'
        write-host $_
        exit 1
    }
}

#Grab the VPN online installer from the web
try {
    Invoke-WebRequest -URI $OnlineInstallerURL -OutFile "$SavePath\$OnlineInstallerName"
} catch {
    Write-host 'Failed to download online VPN installer from fortinet.com. It is needed to determine the latest available VPN version.'
    write-host $_
    exit 1
}

#Run the online installer for a few seconds. I have not found another way to determine the latest version of the VPN client
try {
    $OnlineInstallerProcess = Start-Process -FilePath "$SavePath\$OnlineInstallerName" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 25 # You may need to adjust this value depending on your endpoints' internet connection, etc.
    $OnlineInstallerProcess.Kill()
} catch {
    write-host 'There was a problem running the VPN online installer.'
    write-host $_
    exit 1
}

#Check that the install log exists and grab the line containing the version number if it does
if (Test-Path $InstallerLog) {
    $installerLogContents = get-content $InstallerLog | where-object {$_ -match '.* - This image is version\: '}
} else {
    write-host "$InstallerLog was not found, cannot determine latest available VPN client version."
    exit 1
}

#Isolate the version that will be downloaded - should be the latest version available
try {
    [System.Version]$LatestVersion = $(Select-String -InputObject $installerLogContents -Pattern '\d+\.\d+\.\d+').matches[0].Value.ToString()
} catch {
    write-host "Unable to determine latest VPN version from $InstallerLog."
    write-host $_
    exit 1
}

#If undating, compare new and installed versions and quit if no updates are needed
if (($LatestVersion -le $InstalledVersion) -and ($null -ne $RegistryInstallObject)) {
    Write-Host "Latest available version is $LatestVersion - no update needed."
    exit #Not an error, as the app is already up to date
} else {
    Write-Host "Newer client version available for download: $LatestVersion."
}

#Clean up any existing FortiClient#####.log and FortiClientVPN.exe/msi files from previous installs
if (Test-Path "$InstallerDir\FortiClient*.*") {
    try {
        remove-item "$InstallerDir\FortiClient*.*" -force
    } catch {
        write-host 'There was a problem removing old files from previous installation attempts.'
        write-host $_
        exit 1
    }
}

#Prepare to watch the online installer's temp dir for the creation of a "FortiClient#####.log" file
#This file signifies the offline installer has been downloaded and started by the online installer
$FileWatcher = New-Object System.IO.FileSystemWatcher
$FileWatcher.Path = $InstallerDir
$FileWatcher.Filter = "FortiClient*.log"
$FileWatcher.IncludeSubdirectories = $false
$FileWatcher.EnableRaisingEvents = $true

#Define our detection action - that we will terminate FCT installation once that log file is detected
#This is because the online installer will just update FCT and reboot, ignoring your switches
$FileWatcherAction = {
    Get-Process -ProcessName "FortiClientVPN*" | stop-process -force
}

#Now we have our detection parameters and the action to take - let's watch for the file to show up
Register-ObjectEvent -inputobject $FileWatcher -eventname 'Created' -Action $FileWatcherAction  -SourceIdentifier 'FCTLogWatcher' -SupportEvent

#Start the wait timer
$WaitTimer = [Diagnostics.Stopwatch]::StartNew()

#Run the online installer and then wait/look out for that second stage of the installation to begin
try {
    $OnlineInstallerProcess = Start-Process -FilePath "$SavePath\$OnlineInstallerName" -WindowStyle Hidden -PassThru
} catch {
    write-host 'There was a problem running the VPN online installer.'
    write-host $_
    exit 1
}

#We'll sit here until the online installer was killed, or for a max of 20 minutes
while (-not $OnlineInstallerProcess.HasExited) {
    if ($WaitTimer.elapsed.totalseconds -ge 1200) {
        write-host 'Installation timed out - download took too long.'
        exit 1
    }
}

#Now that we're done waiting, take down the timer and file watcher objects
$WaitTimer.stop()
$WaitTimer = $null
$FileWatcher.Dispose()
$FileWatcher = $null

#Verify we have the offline installer on disk and try to apply the update
if (Test-Path "$InstallerDir\$OfflineInstallerName") {
    try {
        Start-Process -FilePath "$InstallerDir\$OfflineInstallerName" -WindowStyle Hidden -ArgumentList "/quiet /norestart" -Wait
    write-host 'VPN client update successful - a reboot will be needed.'
    $UpdateSuccessful = $true
    } catch {
        write-host 'There was a problem running the VPN offline installer.'
        write-host $_
        exit 1
    }
} else {
    write-host "Did not find '$OfflineInstallerName' installer, cannot proceed."
    exit 1
}

#Re-import the previously saved VPN config if needed
if ($null -ne $RegistryInstallObject) {
    try {
        start-process "$FCCPath" -WindowStyle Hidden -argumentlist "-m all -f   $SavePath\$SettingsBackupFilename -o import -q -i 1 -p $exportPassword" -wait
        write-host 'Original VPN settings successfully restored.'
    } catch {
        write-host 'There was a problem restoring the VPN configuration.'
        write-host $_
        exit 1
    }
}

#Reboot if requested and suspend BitLocker for one reboot if needed
if ($UpdateSuccessful -and ($ENV:RebootOnSuccess -ne 'No')) {
    write-host 'Job configured for reboot - rebooting now.'
     #Check if any drives are using encryption and try to suspend it
    $BitLockerDrives = get-bitlockervolume | where-object protectionstatus -ne 'Off'
    if ($BitLockerDrives) {
        try {
            suspend-bitlocker -mountpoint $BitLockerDrives -rebootcount 1 -erroraction silentlycontinue
        } catch {
            write-host 'There was a problem suspending BitLocker. Rebooting anyway.'
            write-host $_
        }
    }

    #Force reboot if requested, e.g., when user sessions are open on this machine
    if ($ENV:RebootOnSuccess -eq 'Force') {
        try {
            restart-computer -force
        } catch {
            write-host 'Reboot failed.'
            write-host $_
        }
    } else {
        try {
            restart-computer
        } catch {
            write-host 'Reboot failed.'
            write-host $_
        }
    }
}