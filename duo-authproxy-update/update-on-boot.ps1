$UpdateDuoAuthProxyScript = @'
#Duo AuthProxy's display name when installed
$Global:TargetInstalledDisplayName = 'Duo Security Authentication Proxy'
$Global:TargetServiceName = 'DuoAuthProxy'

#Registry locations to check for existing installations
$Global:Targetx64RegistryLocation = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\'
$Global:Targetx86RegistryLocation = 'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\'

#Duo's checksum information URL to determine the latest AuthProxy version available on the web
$Global:TargetChecksumURL = 'https://duo.com/docs/checksums'

Function exit-script() {
    try {
        Get-ScheduledTask -taskname 'Duo AuthProxy update' | `
            ForEach-Object { $_.Triggers[0].EndBoundary = $(Get-Date).ToString('s') ; $_ } | `
                unregister-scheduledtask -Confirm:$false
        write-host 'Removed "Duo AuthProxy update" scheduled task.'
    } catch {
        write-host 'Failed to remove "Duo AuthProxy update" scheduled task.'
    } finally {
        exit
    }
}

Function Get-LatestAuthProxyVersion() {
    #Return the latest Duo authproxy version number fetched from the web if possible
    try {
        #Make three attempts at grabbing this info from duo.com
        for ($attemptNumber = 1; $attemptNumber -lt 4; $attemptNumber++) {
            #Find the URL for the latest Duo Authproxy installer using known naming pattern at Duo's checksums page
            $LatestAuthProxyDownloadURL = $(invoke-webrequest $TargetChecksumURL -UseBasicParsing).links.href | select-string -pattern "/duoauthproxy-[0-9\.]+\.exe" | out-string
            

            #Parse the installer's filename to extract just the version information
            $LatestAuthProxyVersion = $($($LatestAuthProxyDownloadURL -split "duoauthproxy-")[1] -split ".exe" | out-string).trim()
            if ($null -ne $LatestAuthProxyVersion) {
                return $LatestAuthProxyVersion #Stop trying if version number retrieved, or after three tries
            } elseif ($attemptNumber -eq 3) {
                Write-host -message 'Failed to get current version number after 3 attempts.'
            }
        }
    } catch {
        Write-host 'Failed to get current version number from duo.com.'
        Write-host $_
    }
}

Function Find-InstalledDuoAuthProxyVersion() {
    #Return the installed Duo AuthProxy version if found on this PC
    try {
        #Check for Duo uninstall string in x64 registry location
        $RegistryInstallObject = Get-ItemProperty "$Targetx64RegistryLocation*" | where-object -property displayname -Match $TargetInstalledDisplayName
        if ($null -eq $RegistryInstallObject) {
            #Check for uninstall string in x86 registry location
            $RegistryInstallObject = Get-ItemProperty "$Targetx86RegistryLocation*" | where-object -property displayname -Match $TargetInstalledDisplayName
        }
        return $RegistryInstallObject.displayversion
    } catch {
        Write-host 'Could not detect the installed Duo AuthProxy version.'
        Write-host $_
    }
}

Function Find-DuoAuthProxyConfigFile() {
    #Return the directory containing the Duo AuthProxy's config file if found
    try {
        if (test-Path "$Targetx64ConfigDir\$TargetConfigFileName") {
            return $Targetx64ConfigDir
        } elseif (test-path "$Targetx86ConfigDir\$TargetConfigFileName") {
            return $Targetx86ConfigDir
        } else {
            Write-host 'No authproxy.cfg file found. Unable to proceed.'
            Write-host $_
            exit-script
        }
    } catch {
        Write-host 'Problem accessing authproxy.cfg file. Unable to proceed.'
        Write-host $_
        exit-script
    }
}

Function Repair-UpdateNeeded() {
    #Try to fetch and install the latest AuthProxy version available on the web

    param (
        $configFileLocation
    )

    #Where to grab the latest installer
    $DownloadURL = 'https://dl.duosecurity.com/duoauthproxy-latest.exe'

    #Save any downloads to this temp folder
    $SavePath = 'c:\temp'

    #Create the temp folder if it doesn't already exist
    if ( -not (Test-Path -Path $SavePath)) {New-Item -ItemType Directory -Path $SavePath}

    #Try to download the latest installer
    try {
        Invoke-WebRequest -URI $DownloadURL -OutFile "$SavePath\DuoAuthProxyUpdate.exe"
    } catch {
        Write-host 'Failed to download the latest AuthProxy installer.'
        Write-host $_
        exit-script
    }
    
    #Check for and stop any Perch services
    $PerchServices = get-service -name "perch*beat" | Where-Object {$_.Status -eq "Running"}
    if ($PerchServices) {
        try {
            stop-service $PerchServices
            start-sleep -seconds 20
        }
        catch {
            Write-host 'Failed to stop running Perch service(s).'
            Write-host $_
        }
    }

    #Stop the DuoAuthProxy service if its running
    if (get-service -name $TargetServiceName | Where-Object {$_.Status -eq "Running"}) {
        $DuoServiceRunning = $true
        try {
            stop-service -name $TargetServiceName
            start-sleep -seconds 20
        }
        catch {
            Write-host "Failed to stop $TargetServiceName."
            Write-host $_
        }
    } else {
        $DuoServiceRunning = $false
    }

    #Check if any .pyd or .dll files are still locked
    $FileLocked = $false
    $PydsDlls = get-childitem -path "$configFileLocation\..\bin\*" -include "*.pyd","*.dll"
    try {
        foreach ($file in $PydsDlls) {
            $FileCheck = [System.IO.File]::Open($file,'Open','Write')
            $FileCheck.Close()
            $FileCheck.Dispose()
        }
    } catch {
        $FileLocked = $true
    }

    #Attempt install if the file is not locked
    if ($FileLocked) {
        Write-host 'AuthProxy update failed - one or more .pyd/.dll files are locked.'
        Write-host "Update will require reboot. Installer saved in $SavePath."
        exit-script
    } else {
        try {
            start-process -FilePath "$SavePath\DuoAuthProxyUpdate.exe" -ArgumentList "/S" -WarningAction SilentlyContinue -wait
            Write-host 'AuthProxy update was successfully installed.'
        } catch {
            Write-host 'AuthProxy update failed.'
            Write-host "Check log\install.log. Installer saved in $SavePath."
            Write-host $_
            exit-script
        }
    }

    #Restart DuoAuthProxy service if it was already running
    if ($DuoServiceRunning) {
        try {start-service -name $TargetServiceName -WarningAction SilentlyContinue}
        catch {
            Write-host "$TargetServiceName failed to start."
            Write-host $_
        }
    } else {
        Write-host 'Duo service was not already running. Opting not to try starting it.'
    }

    #Restart Perch services if applicable
    if ($PerchServices) {
        try {start-service $PerchServices}
        catch {
            Write-host 'Perch service(s) failed to start.'
            Write-host $_
        }
    }
}

##########
### Begin the main body of the component
#

#First, make sure we have Duo installed on this machine. Quit if not found
Write-Host 'Checking registry to confirm the Duo Authentication Proxy is installed...'
$InstalledAuthProxyVersion = Find-InstalledDuoAuthProxyVersion

#Ensure we are using TLS 1.2 for web requests going forward
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($null -eq $InstalledAuthProxyVersion) {
    exit-script
} else {
    #Verify we can reach duo.com
    try {
        $Timeout = New-TimeSpan -Minutes 5
        $EndTime = $(Get-Date).add($Timeout)

        do {
            if (Test-Connection -ComputerName "duo.com") {
                break
            } else {
                Start-Sleep -seconds 5
            }
        } until ($(Get-Date) -ge $EndTime)
    } catch {
        write-host $_
    }

    #Then see what the newest version available for download is
    Write-Host 'Checking latest AuthProxy version available for download...'
    $LatestAuthProxyVersion = Get-LatestAuthProxyVersion

    #Compare installed version to latest available version
    if ($null -eq $LatestAuthProxyVersion) {
        Write-host "Unable to determine if the installed AuthProxy version $InstalledAuthProxyVersion is up to date."
        exit-script
    } elseif ($InstalledAuthProxyVersion -ne $LatestAuthProxyVersion) {
        Write-host "Installed version $InstalledAuthProxyVersion needs update to $LatestAuthProxyVersion."
    } else {
        Write-host "Installed version $InstalledAuthProxyVersion is up to date."
        exit-script
    }

    $ConfigFileLocation = Find-DuoAuthProxyConfigFile
    Repair-UpdateNeeded($ConfigFileLocation)
}

exit-script
'@

$SaveDirectory = 'c:\temp'
if ( -not (Test-Path -Path $SaveDirectory)) {New-Item -ItemType Directory -Path $SaveDirectory}
$FullScriptPath = "$SaveDirectory\Update-DuoAuthproxy.ps1"
$UpdateDuoAuthProxyScript | Out-File -FilePath $FullScriptPath

$TaskTrigger = New-ScheduledTaskTrigger -AtStartup
$TaskAction = New-ScheduledTaskAction -Execute 'powershell.exe'  -Argument "-ExecutionPolicy bypass -File ""$($FullScriptPath)"" -Wait"
$TaskSettings = New-ScheduledTaskSettingsSet -DeleteExpiredTaskAfter 00:00:00
$TaskDescription = 'This task is intended to run once on next boot and then be deleted.'

Register-ScheduledTask -force -taskname 'Duo AuthProxy update' -user 'NT AUTHORITY\SYSTEM' -InputObject (
    (
        New-ScheduledTask -Action $TaskAction -Trigger $TaskTrigger -Settings $TaskSettings -Description $TaskDescription
    ) | foreach-object { $_.Triggers[0].EndBoundary = $((Get-Date).AddDays(7)).ToString('s') ; $_ }
)