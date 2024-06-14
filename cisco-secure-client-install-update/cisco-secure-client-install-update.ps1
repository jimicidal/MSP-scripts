# The new version number we're installing
[System.Version]$NewVersion = '5.1.3.62'

# Location of Umbrella's top-level config folder
$CSCLocation = "$($ENV:SystemDrive)\ProgramData\Cisco\Cisco Secure Client\Umbrella"

function Get-UmbrellaJSON {
    # This function is redacted as it contained private information. It interfaced with an internal
    # secrets manager, but now only returns a hard-coded JSON string to resemble the secret it would
    # have retrieved. Just replace this code to grab the JSON config from wherever you have stored it.

    $madeUpValues = @{
        fingerprint = ab9ab9ab9ab9ab9ab9ab9ab9aba9b9ab9ab9ab9a9b
        orgid = 0202020020202020020202020202
        userid = 010101010101010
    } | ConvertTo-Json

    return $madeUpValues
}

# Test whether <API> has a retrievable umbrella configuration for this client
try {
    $APIValue = $null
    write-host 'Checking <API> for existing Umbrella configuration.'
    $APIValue = Get-UmbrellaJSON
    if ($null -eq $APIValue) {
        Write-Host '  -- No configuration found, cannot proceed.'
        write-host '  -- Please notify Security team to add an Umbrella config JSON to <API>.'
        exit 1
    }
} catch {
    Write-Host '  -- Unable to retreive config from <API>.'
    write-host $_
    exit 1
}

# Check whether Secure Client is installed so we don't modify anything that doesn't need to be changed
$SecureClientInstalled = Get-WmiObject -Class Win32_Product | Where-Object {($_.vendor -match "^Cisco ") -and ($_.name -match 'Secure Client')} | select-object Name, Version
if (-not $SecureClientInstalled) {
    write-host 'Cisco Secure Client is not already installed.'
} else {
    # Grab version numbers for the individual components that are installed
    $CoreInstalled = $SecureClientInstalled | Where-Object {$_.name -match 'AnyConnect VPN'}
    $UmbrellaInstalled = $SecureClientInstalled | Where-Object {$_.name -match 'Umbrella'}
    $DARTInstalled = $SecureClientInstalled | Where-Object {$_.name -match 'Diagnostics and Reporting Tool'}
    write-host "Cisco Secure Client v$($CoreInstalled.version) is already installed."
}

# Import the certificate to machine root
try {
    import-certificate -certstorelocation cert:\localmachine\root -filepath ".\Cisco_Umbrella_Root_CA.cer" | out-null
    write-host 'Imported the SSL inspection certificate.'
} catch {
    write-host 'There was a problem importing the SSL inspection certificate.'
    write-host $_
}

# Get any running Cisco "CSC" services and stop them. We'll be re-starting them later
$RunningCSCServices = get-service -displayname "Cisco Secure Client*" | where-object {$_.status -eq 'Running'}
if ($RunningCSCServices) {
    try {
        stop-service $RunningCSCServices
        write-host 'Stopped running CSC services.'
    } catch {
        write-host 'There was a problem stopping CSC services - unable to perform an update.'
        write-host $_
        exit 1
    }
}

# Ignore installation of CSC core if no update is needed
if (($CoreInstalled) -and ($CoreInstalled.version -ge $NewVersion)) {
    write-host "Ignoring installed core version $($CoreInstalled.version)."
} else {
    # Otherwise we will install it with the arguments defined here
    try {
        write-host "Installing CSC core v$NewVersion."
        $coreInstaller = Join-Path -Path $PSScriptRoot -ChildPath 'cisco-secure-client-win-5.1.3.62-core-vpn-predeploy-k9.msi'
        $coreArgs = @(
            ('/package {0}' -f $coreInstaller),
            '/norestart',
            '/quiet',
            'PRE_DEPLOY_DISABLE_VPN=1'
        )
        Start-Process -FilePath 'msiexec.exe' -ArgumentList $coreArgs -Wait
        write-host '  -- CSC core installed successfully.'
    } catch {
        write-host '  -- There was a problem installing CSC core.'
        write-host $_
    }
}

# Ignore installation of Umbrella component if no update is needed
if (($UmbrellaInstalled) -and ($UmbrellaInstalled.version -ge $NewVersion)) {
    write-host "Ignoring installed Umbrella version $($UmbrellaInstalled.version)."
} else {
    # Otherwise we will install it with the arguments defined here
    try {
        write-host "Installing CSC Umbrella v$NewVersion."
        $umbrellaInstaller = Join-Path -Path $PSScriptRoot -ChildPath 'cisco-secure-client-win-5.1.3.62-umbrella-predeploy-k9.msi'
        $umbrellaArgs = @(
            ('/package {0}' -f $umbrellaInstaller),
            '/norestart',
            '/quiet'
        )
        Start-Process -FilePath 'msiexec.exe' -ArgumentList $umbrellaArgs -Wait
        write-host '  -- CSC Umbrella installed successfully.'
    } catch {
        write-host '  -- There was a problem installing CSC Umbrella.'
        write-host $_
    }
}

# If DART is already installed, update it as necessary. Otherwise ignore this component
if (($DARTInstalled) -and ($DARTInstalled.version -ge $NewVersion)) {
    write-host "Ignoring installed DART version $($DARTInstalled.version)"        
} elseif ($DARTInstalled) {
    try {
        write-host "Installing CSC DART v$NewVersion."
        $dartInstaller = Join-Path -Path $PSScriptRoot -ChildPath 'cisco-secure-client-win-5.1.3.62-dart-predeploy-k9.msi'
        $dartArgs = @(
            ('/package {0}' -f $dartInstaller),
            '/norestart',
            '/quiet'
        )
        Start-Process -FilePath 'msiexec.exe' -ArgumentList $dartArgs -Wait
        write-host '  -- CSC DART updated successfully.'
    } catch {
        write-host '  -- There was a problem updating CSC DART.'
        write-host $_
    }
}

# Give some time to finish writing to log files
Start-Sleep -Seconds 5

# Delete Umbrella's \data subfolder per Cisco documentation on changes to OrgInfo.json
if (test-path -Path "$CSCLocation\data") {
    Get-ChildItem "$CSCLocation\data\*" -Recurse | Remove-Item -Force -Recurse -Confirm:$false
    write-host 'Data subfolder removed.'
}

# Create the \umbrella subfolder if it doesn't already exist
if (-not (test-path -Path $CSCLocation)) {
    New-Item -Path $CSCLocation -ItemType Directory -Force | Out-Null
}

# Create or overwrite OrgInfo.json with new data
try {
    Set-Content -Path "$CSCLocation\OrgInfo.json" -value $APIValue -force
    write-host 'OrgInfo.json file written.'
} catch {
    write-host 'There was a problem writing the OrgInfo.json file.'
    write-host $_
    exit 1
}

# Re-start the CSC services that were running earlier
if ($RunningCSCServices) {
    try {
        start-service $RunningCSCServices
        write-host 'Re-started CSC services.'
    } catch {
        write-host 'There was a problem re-starting CSC services - a reboot may be needed.'
        write-host $_
    }
}