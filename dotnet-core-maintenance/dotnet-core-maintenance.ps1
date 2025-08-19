<# This script is made for Datto RMM and requires input variables configured for the component to run properly:
    InputProcedure          Selection   Install | Update | Upgrade to channel | Audit EOL dates | Keep latest | Uninstall channel | Uninstall specific version | Uninstall all
    InputProduct            Selection   Hosting bundle | ASP.NET runtime | Desktop runtime | Standalone runtime | SDK
    InputChannel            Selection   5.0 | 6.0 | 7.0 | 8.0 | 9.0
    InputArchitecture       Selection   win-x64 | win-x86 | x64 and x86
    InputSpecificVersion    Text box    e.g. 8.0.16
    InputRemoveEOLVersions  Boolean     $true | $false #>

#------------------------------------------------------------------
#                           DEFINITIONS
#------------------------------------------------------------------

# Directory where we're saving any downloaded installer files
$SavePath = "$($ENV:SystemDrive)\temp"

<# These product names have three parts and are used to refer to the same product in different ways throughout the script:
    - FriendlyName - the shortened version of the product name for the person running the RMM component
        - These should equal the names you entered for the 'InputProduct' variable in the RMM component config
    - InstalledName - regular expression that matches only that product when installed, regardless of CPU architecture
        - Each one needs parentheses around it to make a capture group; all groups are then joined by pipes (`|`)
    - URLName - a string that equals the corresponding piece of the URL needed to download that product
        - To find these, download the package manually and look at the download URL #>
$DotnetProductNames = [System.Collections.ArrayList]::new()
$DotnetProductNames.Add([PSCustomObject]@{
                            FriendlyName = 'Hosting bundle'
                            InstalledName = '(Microsoft \.NET .* \- Windows Server Hosting)'
                            URLName = 'aspnetcore-runtime'}) | Out-Null
$DotnetProductNames.Add([PSCustomObject]@{
                            FriendlyName = 'ASP.NET runtime'
                            InstalledName = '(Microsoft ASP\.NET Core .* \- Shared Framework)'
                            URLName = 'aspnetcore-runtime'}) | Out-Null
$DotnetProductNames.Add([PSCustomObject]@{
                            FriendlyName = 'Desktop runtime'
                            InstalledName = '(Microsoft Windows Desktop Runtime \- )'
                            URLName = 'windowsdesktop'}) | Out-Null
$DotnetProductNames.Add([PSCustomObject]@{
                            FriendlyName = 'Standalone runtime'
                            InstalledName = '(Microsoft \.NET Runtime ?\- )'
                            URLName = 'runtime'}) | Out-Null
$DotnetProductNames.Add([PSCustomObject]@{
                            FriendlyName = 'SDK'
                            InstalledName = '(Microsoft \.NET SDK )'
                            URLName = 'sdk'}) | Out-Null
$CombinedProductNames = ($DotnetProductNames.InstalledName) -join "|"

#------------------------------------------------------------------
#                           FUNCTIONS
#------------------------------------------------------------------

function ConvertTo-NameObject {
    # Match a friendly name or installed product name to a name object in the $DotnetProductNames arraylist above
    param (
        [Parameter(Mandatory=$true)]
            $NameValue,
        [Parameter(Mandatory=$true)]
            $NameType
    )

    switch -regex ($NameType) {
        'FriendlyName|InstalledName' {
            foreach ($nameObject in $DotnetProductNames) {
                if ($NameValue -match $nameObject.$NameType) {return $nameObject}
            }
        } default {return $null}
    }
}

Function Get-InstalledInstances {
    param([switch]$PrintToScreen)

    # Here's where we will store the important info about all the installed dotnet instances found
    $InstalledProducts = @()

    try {
        # Try to find all installed packages that match the regular expressions above
        $InstalledPackages = get-package -providername 'Programs' -force | where-object {($_.name -match $CombinedProductNames)}
    } catch {
        write-host 'There was a problem finding installed instances of .NET core.'
        write-host $_
        return
    }

    if ($InstalledPackages) {
        # If we found any installed instances of dotnet, now we want to make this info usable
        foreach ($pkg in $InstalledPackages) {

            # Native PowerShell name for display in stdout
            $PackageName = $pkg.name

            # Get the full corresponding name object
            $ConvertedName = ConvertTo-NameObject -NameValue $pkg.name -NameType 'InstalledName'
            
            # The channel is needed for the download URL and EOL date
            $PackageChannel = [System.Version](($pkg.Version.Split('.')[0]) + ".0")

            # SDK version is taken from the package name, all others use as provided
            if ($pkg.name -match 'SDK') {
                $PackageVersion = [System.Version]($pkg.name.split(' ')[3])
            } else {
                $PackageVersion = [System.Version](($pkg.Version.Split('.')[0..2]) -join '.')
            }

            # The architecture is taken from the friendly package name - the hosting package has no architecture
            switch -regex ($pkg.name) {
                '\(x64\)$' {
                    $PackageArchitecture = 'win-x64'
                } '\(x86\)$' {
                    $PackageArchitecture = 'win-x86'
                } 'Windows Server Hosting$' {
                    $PackageArchitecture = ''
                }
            }
            
            # Store the usable info in a custom object and add that to the array we're returning
            $InstalledProducts += [PScustomobject]@{
                Name = $PackageName
                NameObject = $ConvertedName
                Channel = $PackageChannel
                Version = $PackageVersion
                Architecture = $PackageArchitecture
            }
        }
    }

    if ($PrintToScreen) {
        if ($InstalledProducts) {write-host " -"$($($InstalledProducts.name) -join "`r`n - ")}
        else {write-host ' - None'}
    }

    return $InstalledProducts
}

Function Find-DownloadURL() {
    # You can provide either a .NET product/channel/architecture to get the latest download URL for that channel,
    # you can provide a product/specific version/architecture to get the URL for that specific version,
    # or pipe in an $InstalledProduct from to Get-InstalledInstances function if you already have it
    [CmdletBinding(DefaultParameterSetName='Latest')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Latest')]
        [Parameter(Mandatory=$true, ParameterSetName='Specific')]
        [string]$Product,               # runtime | sdk | aspnetcore-runtime | windowsdesktop

        [Parameter(Mandatory=$true, ParameterSetName='Latest')]
        [string]$Channel,               # 9.0 | 8.0 | 7.0 | 6.0 | 5.0

        [Parameter(Mandatory=$false, ParameterSetName='Latest')]
        [Parameter(Mandatory=$false, ParameterSetName='Specific')]
        [string]$Architecture,          # win-x64 | win-x86 | ''

        [Parameter(Mandatory=$true, ParameterSetName='Specific')]
        [string]$Version,               # e.g., 8.0.7

        [Parameter(Mandatory=$true, ParameterSetName='Object', ValueFromPipeline)]
        [pscustomobject]$InstallObject
    )

    # Release feed URL format comes from "https://github.com/dotnet/core/blob/main/release-notes/releases-index.json"
    # I've chosen not to check this release index programmatically as some client environments might restrict access to GitHub
    # If this function stops returning valid files, you may need to check whether the release feed URL format has changed
    $ReleaseFeedURLFormat = "https://builds.dotnet.microsoft.com/dotnet/release-metadata/{0}/releases.json"

    # If you requested the URL for a specific version, the channel is inferred from the version you provide
    switch ($PsCmdlet.ParameterSetName) {
        'Specific' {
            $Channel = $(($Version.Split('.')[0]) + '.0')
        } 'Object' {
            $Product = $InstallObject.nameobject.URLName
            $Architecture = $InstallObject.architecture
            $Version = $InstallObject.version
            $Channel = $InstallObject.channel
        }
    }

    # The full release feed URL is completed by inserting the channel number
    $ReleaseFeedURL = $ReleaseFeedURLFormat -f $Channel

    # This object will be the one returned by the function after filling in the details
    $MatchingObject = [pscustomobject]@{
        LatestVersion = ''
        LatestSDK = ''
        RequestedVersion = ''
        EOLDate = ''
        FileName = ''
        URL = ''
        Hash = ''
    }

    # Fetch the release feed for info on available downloads
    try {
        $FeedContent = (Invoke-webrequest $ReleaseFeedURL -UseBasicParsing).'content'
    } catch {
        write-host "There was a problem loading release feed URL $ReleaseFeedURL."
        write-host $_
        return $null
    }

    # If you requested the latest version, set the $Version parameter to the latest version found
    # This way we can use the same line to extract download details whether you provided a specific verion or not
    switch ($PsCmdlet.ParameterSetName) {
        'Latest' {$Version = ($FeedContent | convertfrom-json).'latest-release'}
    }

    # Gather details about the feed and installer
    $ProductLatestVersion = ($FeedContent | convertfrom-json).'latest-release'
    $ProductLatestSDK = ($FeedContent | convertfrom-json).'latest-sdk'
    try {
        $ProductEOLDate = (($FeedContent | convertfrom-json).'eol-date' | get-date -ErrorAction Ignore)
    } catch {
        write-host "There was a problem getting the EOL date for channel $Channel."
    }

    #$FoundObject = ($FeedContent | convertfrom-json | Select-Object -ExpandProperty 'releases' | where-object 'release-version' -eq "$Version" | Select-Object -ExpandProperty "$Product" | Select-Object -ExpandProperty 'files' | where-object {($_.rid -eq "$architecture") -and ($_.name -match ".exe$")})
    # Specific SDKs are found in a slightly different area vs other products
    if (($Product -eq 'sdk')<# -and ($PsCmdlet.ParameterSetName -eq 'Specific')#>) {
        $FoundObject = $($($($FeedContent | convertfrom-json).releases.sdks | where-object 'version' -eq "$Version").'files' | where-object {($_.rid -eq "$architecture") -and ($_.name -match ".exe$")})
    } else {
        $FoundObject = $($($($($FeedContent | convertfrom-json).releases | where-object 'release-version' -eq "$Version")."$Product").'files' | where-object {($_.rid -eq "$architecture") -and ($_.name -match ".exe$")})
    }

    if ($null -eq $FoundObject) {
        write-host "There was a problem finding a URL for '$Product $Version $Architecture'."
        return
    } else {
        # Build our return object
        $MatchingObject.LatestVersion = $ProductLatestVersion
        $MatchingObject.LatestSDK = $ProductLatestSDK
        $MatchingObject.RequestedVersion = $Version
        $MatchingObject.EOLDate = $ProductEOLDate
        $MatchingObject.FileName = ($FoundObject).'name'
        $MatchingObject.URL = ($FoundObject).'url'
        $MatchingObject.Hash = ($FoundObject).'hash'

        return $MatchingObject
    }
}

Function Get-Installer() {
    # You can provide a .NET product/channel/architecture to get the latest installer for that channel,
    # you can provide a .NET product/architecture/version to get the installer of that specific version,
    # or pipe in the $MatchingObject from the Find-DotnetDownloadURL function if you already have it
    [CmdletBinding(DefaultParameterSetName='Latest')]
    param(
        [Parameter(Mandatory=$true, ParameterSetName='Latest')]
        [Parameter(Mandatory=$true, ParameterSetName='Specific')]
        [string]$Product,               # runtime | sdk | aspnetcore-runtime | windowsdesktop

        [Parameter(Mandatory=$true, ParameterSetName='Latest')]
        [string]$Channel,               # 9.0 | 8.0 | 7.0 | 6.0 | 5.0

        [Parameter(Mandatory=$false, ParameterSetName='Latest')]
        [Parameter(Mandatory=$false, ParameterSetName='Specific')]
        [string]$Architecture,          # win-x64 | win-x86 | ''

        [Parameter(Mandatory=$true, ParameterSetName='Specific')]
        [string]$Version,               # e.g., 8.0.7

        [Parameter(Mandatory=$true, ParameterSetName='Object', ValueFromPipeline)]
        [pscustomobject]$DownloadObject # For removing an installed product
    )

    # Grab the appropriate download URL plus related details from Microsoft
    switch ($PsCmdlet.ParameterSetName) {
        'Latest' {
            $NewInstaller = Find-DownloadURL -Product $Product -Channel $Channel -Architecture $Architecture
        } 'Specific' {
            $NewInstaller = Find-DownloadURL -Product $Product -Architecture $Architecture -Version $Version
        } 'Object' {
            $NewInstaller = $DownloadObject
        }
    }

    if ($null -eq ($NewInstaller.FileName)) {
        write-host 'There was a problem finding an installer to download.'
        return
    } else {
        # Download and save the file to our $SavePath
        try {
            Invoke-WebRequest $NewInstaller.URL -OutFile "$SavePath\$($NewInstaller.FileName)" -UseBasicParsing
        } catch {
            write-host "There was a problem downloading $($NewInstaller.FileName)."
            write-host $_
            return
        }

        # Verify hash match - delete the file if no match
        $DownloadedFileHash = $(get-filehash "$SavePath\$($NewInstaller.FileName)" -Algorithm 'SHA512').Hash.ToLower()
        if ($DownloadedFileHash -eq $NewInstaller.Hash.ToLower()) {
            return $($NewInstaller.FileName)
        } else {
            write-host 'There was a problem with the downloaded file.'
            write-host 'SHA512 hash did not match the hash provided by Microsoft.'
            try {
                Remove-Item "$SavePath\$($NewInstaller.FileName)"
                write-host "Downloaded file $($NewInstaller.FileName) was deleted."
            } catch {
                write-host 'There was a problem deleting the downloaded file.'
                write-host $_
                return
            }
        }
    }
}

Function Install-Uninstall() {
    # Pipe in a filename and whether to install the package or uninstall it
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline)]
            $Filename,
        [Parameter(Mandatory=$true)]
            $Procedure
    )

    # Check that the filename provided is valid
    if ( -not (Test-Path "$SavePath\$FileName")) {
        Write-Host "There was a problem with the path $SavePath\$FileName."
        Write-Host 'Unable to process this file.'
        return
    }

    # Set appropriate arguments for the procedure
    if (($Procedure -eq 'Install') -or ($Procedure -eq 'Uninstall')) {
        $ChosenArguments = "/" + $Procedure.ToLower() + " /quiet /norestart"
    } else {
        Write-Host "There was a problem with the request to $procedure $FileName."
        return
    }

    # Do the thing
    try {
        #write-host $Procedure"ing..."
        Start-Process -FilePath "$SavePath\$FileName" -ArgumentList $ChosenArguments -wait
        #write-host 'OK!'
    } catch {
        Write-Host "There was a problem trying to"$Procedure.ToLower()"$Filename."
        Write-Host $_
    }
}

function Find-Oldest {
    # From installed products of the same type, find multiples of the same architecture and return all but the latest version 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
            $ItemArray,
        [Parameter(Mandatory=$true)]
            $Architecture
    )

    $MatchingArch = $($ItemArray | Where-object {$_.architecture -eq $Architecture} | Sort-Object -Descending -Property 'Version')

    if ($MatchingArch.count -gt 1) {return $MatchingArch[1..($MatchingArch.count -1)]
    } else {return $null}
}

function Find-EolDates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ValueFromPipeline)]
            [PSCustomObject]$InstalledProducts,
            [switch]$PrintToScreen
    )

    # Loop through installed products and check EOL dates
    if ($InstalledProducts) {
        $Today = Get-Date -DisplayHint 'Date'

        $ExpiredProducts = [System.Collections.ArrayList]::new()
        $ExpiringProducts = [System.Collections.ArrayList]::new()

        foreach ($Product in $InstalledProducts) {
            #$Record = Find-DownloadURL -Product $Product.NameObject.URLName -Architecture $Product.Architecture -Version $Product.Version
            $Record = Find-DownloadURL -InstallObject $Product
            $Expiration = Get-Date $Record.EOLDate -DisplayHint 'Date'
            if ($Expiration -le $Today) {$ExpiredProducts.Add($Product) | Out-Null}
            elseif ($Expiration -le $Today.AddDays(90)) {$ExpiringProducts.Add($Product) | Out-Null}
        }
    } else {
        if ($PrintToScreen) {Write-Host ' - No products installed.'}
        return $null
    }

    # Report if no EOL dates apply
    if ((-not $ExpiringProducts) -and (-not $ExpiredProducts) -and ($PrintToScreen)) {
        write-host ' - No issues found.'
    }

    # Report on any upcoming EOL dates
    if (($ExpiringProducts) -and ($PrintToScreen)) {
        write-host '- Expiring within 90 days:'
        foreach ($product in $ExpiringProducts) {write-host " - $($Product.NameObject.FriendlyName) $($Product.Version) $($Product.Architecture)."}
    }

    # Return list of products that have already expired
    if ($ExpiredProducts) {
        if ($PrintToScreen) {
            write-host '- Already expired:'
            foreach ($product in $ExpiredProducts) {write-host " - $($Product.NameObject.FriendlyName) $($Product.Version) $($Product.Architecture)."}
        }
        return $ExpiredProducts
    } else {return $null}
}

function Publish-Config {
    if ($Requested.Procedure -eq 'Install') {
        $PreambleFormat = "Job is configured to install the latest .NET Core {0} in channel {1}{2}."
        $Preamble = $PreambleFormat -f $Requested.Product.FriendlyName, $Requested.Channel, $Requested.DisplayArch
        write-host $Preamble
    } elseif ($Requested.Procedure -eq 'Update') {
        Write-host 'Job is configured to update installed instances of .NET Core to the latest version within their channel.'
    } elseif ($Requested.Procedure -eq 'Upgrade to channel') {
        $PreambleFormat = "Job is configured to upgrade installed instances of .NET Core to channel {0}."
        $Preamble = $PreambleFormat -f $Requested.Channel
        write-host $Preamble
    } elseif ($Requested.Procedure -eq 'Audit EOL dates') {
        write-host 'Job is configured to audit end-of-life dates for installed instances of .NET Core.'
    } elseif ($Requested.Procedure -eq 'Keep latest') {
        Write-host 'Job is configured to keep only the latest version out of any duplicate .NET Core products installed.'
    } elseif ($Requested.Procedure -eq 'Uninstall channel') {
        $PreambleFormat = "Job is configured to uninstall .NET Core products in channel {0}."
        $Preamble = $PreambleFormat -f $Requested.Channel
        write-host $Preamble
    } elseif ($Requested.Procedure -eq 'Uninstall specific version') {
        $PreambleFormat = "Job is configured to uninstall .NET Core {0} {1}{2}."
        $Preamble = $PreambleFormat -f $Requested.Product.FriendlyName, $Requested.SpecificVersion, $Requested.DisplayArch
        write-host $Preamble
    } elseif ($Requested.Procedure -eq 'Uninstall all') {
        Write-host 'Job is configured to uninstall all instances of .NET Core.'
    }

    if ($Requested.RemoveEOLVersions) {Write-Host 'End-of-life products will be uninstalled.'}
}

#------------------------------------------------------------------
#                           RUNTIME CONFIG
#------------------------------------------------------------------

# Basic initial capture of this script's runtime values provided by Datto RMM. Additional processing follows
$Requested = [pscustomobject]@{
    Procedure = $env:InputProcedure
    Product = $env:InputProduct                         # Further processed below
    Channel = $env:InputChannel
    Architecture = $env:InputArchitecture               # Further processed below
    DisplayArch = $null                                 # Further processed below
    SpecificVersion = $env:InputSpecificVersion
    RemoveEOLVersions = $env:InputRemoveEOLVersions     # Further processed below
}

################################################################### Hard-coded values for local testing outside of Datto RMM ###########################################
$Requested = [pscustomobject]@{
    Procedure = 'Update'                # Uninstall channel | Uninstall specific version | Keep latest
    Product = 'Standalone runtime'      # Hosting bundle | ASP.NET runtime
    Channel = '7.0'
    Architecture = 'win-x64'            # 'x64 and x86'
    DisplayArch = $null
    SpecificVersion = '7.0.20'
    RemoveEOLVersions = $true
}
################################################################### Hard-coded values for local testing outside of Datto RMM ###########################################>

# Set a multi-name object as the requested product
$Requested.Product = ConvertTo-NameObject -NameValue $Requested.Product -NameType 'FriendlyName'

# The hosting bundle has no architecture, otherwise make an array of architectures if we're handling both
if ($Requested.Product.FriendlyName -eq 'Hosting bundle') {$Requested.Architecture = ''}
elseif ($Requested.Architecture -match 'and') {
    $Requested.Architecture = @("win-x64","win-x86")
    $Requested.DisplayArch = ", $($Requested.Architecture -join ' & ')"
} else {$Requested.DisplayArch = ", $($Requested.Architecture)"}

# Set an actual Boolean value over Datto RMM's provided string value - You'll want to comment this out for local testing
if ($env:InputRemoveEOLVersions -eq $true) {$Requested.RemoveEOLVersions = $true} else {$Requested.RemoveEOLVersions = $false}

#------------------------------------------------------------------
#                           MAIN SCRIPT LOGIC
#------------------------------------------------------------------

Publish-Config # State the runtime preferences in STDOUT

# Get & display .NET products before any changes are made
write-host "`r`nCurrently installed products:"
$InstalledDotnetInstances = Get-InstalledInstances -PrintToScreen

# Create the temp folder if it doesn't already exist
if ( -not (Test-Path -Path $SavePath)) {New-Item -ItemType Directory -Path $SavePath}

# Track whether we've added or removed any versions of .NET Core
$ChangesMade = $false

write-host # Blank line for STDOUT readability

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

if ($Requested.Procedure -eq 'Install') {
    write-host 'Installing requested products:'
    # Loop through 0-2 architectures and download/process each one
    foreach ($arch in $Requested.Architecture) {
        write-host " - Installing $($Requested.Product.FriendlyName) $($arch)..."
        Get-Installer -product $Requested.Product.URLName -channel $Requested.Channel -architecture $arch | Install-Uninstall -Procedure 'Install'
        $ChangesMade = $true
    }
} elseif ($Requested.Procedure -eq 'Update') {
    write-host 'Updating products:'

    # Loop through installed products and compare their version against the latest available
    if ($InstalledDotnetInstances) {
        foreach ($prod in $InstalledDotnetInstances) {
            $latestAvailable = Find-DownloadURL -InstallObject $prod
            if ($prod.NameObject.FriendlyName -eq 'SDK') {
                $CompareVersion = $latestAvailable.LatestSDK
            } else {
                $CompareVersion = $latestAvailable.LatestVersion
            }

            # Update if needed and keep track of whether any changes needed to be made
            if ($prod.Version -lt $CompareVersion) {
                write-host " - Updating $($prod.NameObject.FriendlyName) $($prod.Channel) $($prod.Architecture)..."
                Get-Installer -Product $prod.NameObject.URLName -Channel $prod.Channel -Architecture $prod.Architecture | Install-Uninstall -Procedure 'Install'
                $ChangesMade = $true
            }
        }
        if (-not $ChangesMade) {write-host ' - No updates needed.'}
    } else {
        write-host ' - No products installed.'
    }
} elseif ($Requested.Procedure -eq 'Upgrade to channel') {
    write-host 'Upgrading products:'

    # Loop though installed products and check if they are from a lesser channel number
    if ($InstalledDotnetInstances) {
        foreach ($prod in $InstalledDotnetInstances) {
            if ($prod.channel -lt $Requested.Channel) {
                # If it needs to be upgraded, install the latest version from the new channel and remove the old one
                write-host " - Upgrading $($prod.NameObject.FriendlyName) $($prod.architecture)..."
                Get-Installer -product $prod.NameObject.URLName -channel $Requested.Channel -architecture $prod.architecture | Install-Uninstall -Procedure 'Install'
                Get-Installer -product $prod.NameObject.URLName -channel $prod.channel -architecture $prod.architecture | Install-Uninstall -Procedure 'Uninstall'
                $ChangesMade = $true
            }
        }
        if (-not $ChangesMade) {write-host ' - No upgrades needed.'}
    } else {
        write-host ' - No products installed.'
    }

    if ($ChangesMade -eq $false) {write-host 'No upgrades needed.'}
} elseif ($Requested.Procedure -eq 'Audit EOL dates') {
    write-host 'End-of-life audit:'
    if ($InstalledDotnetInstances) {
        Find-EolDates -InstalledProducts $InstalledDotnetInstances -PrintToScreen | Out-Null
    } else {
        write-host ' - No products installed.'
    }
} elseif ($Requested.Procedure -eq 'Keep latest') {
    write-host 'Checking for duplicates:'

    if ($InstalledDotnetInstances) {
        $EntriesToRemove = [System.Collections.ArrayList]::new()

        # Loop through product types to check for multiples of each product
        foreach ($ProductType in $DotnetProductNames) {
            $Entries = $InstalledDotnetInstances.Where({($_.NameObject.FriendlyName -eq $ProductType.FriendlyName)})

            # Found multiples, but they are potentially different architectures
            if ($Entries.count -gt 1) {

                # Accrue a list of candidates for removal
                foreach ($Architecture in 'win-x64','win-x86','') {
                    $Removals = Find-Oldest -ItemArray $Entries -Architecture $Architecture
                    if ($Removals) {$EntriesToRemove.Add($Removals) | Out-Null}
                }
            }
        }

        # Remove everything that was found
        if ($EntriesToRemove) {
            foreach ($Entry in $EntriesToRemove) {
                write-host " - Removing $($Entry.NameObject.FriendlyName) $($Entry.Version) $($Entry.Architecture)..."
                Get-Installer -Product $Entry.NameObject.URLName -Architecture $Entry.Architecture -Version $Entry.Version | Install-Uninstall -Procedure 'Uninstall'
                $ChangesMade = $true
            }
        } else {
            write-host ' - No duplicates to remove.'
        }
    } else {
        write-host ' - No products installed.'
    }
} elseif ($Requested.Procedure -eq 'Uninstall channel') {
    Write-Host 'Uninstalling products:'

    # Loop through installed products and check for any that match our channel
    if ($InstalledDotnetInstances) {
        foreach ($prod in $InstalledDotnetInstances) {
            if ($prod.channel -eq $Requested.Channel) {
                write-host " - Removing $($prod.NameObject.FriendlyName) $($prod.Version) $($prod.Architecture)..."
                Get-Installer -Product $prod.NameObject.URLName -Architecture $prod.Architecture -Version $prod.Version | Install-Uninstall -Procedure 'Uninstall'
                $ChangesMade = $true
            }
        }

        if ($ChangesMade -eq $false) {write-host ' - No products in channel.'}
    } else {
        write-host ' - No products installed.'
    }
} elseif ($Requested.Procedure -eq 'Uninstall specific version') {
    write-host 'Uninstalling requested product:'

    # Loop through installed products and check for any that match our specific version/architecture
    if ($InstalledDotnetInstances) {
        $EntriesToRemove = [System.Collections.ArrayList]::new()

        foreach ($arch in $Requested.Architecture) {
            $MatchingEntries = $null
            $MatchingEntries = $InstalledDotnetInstances | where-object { `
                                                                ($_.NameObject.FriendlyName -eq $Requested.Product.FriendlyName) -and `
                                                                ($_.version -match $Requested.SpecificVersion) -and `
                                                                ($_.architecture -eq $arch)}
            if ($MatchingEntries) {$EntriesToRemove.Add($MatchingEntries) | Out-Null}
        }

        # Remove everything that was found
        if ($EntriesToRemove) {
            foreach ($Entry in $EntriesToRemove) {
                write-host " - Removing $($Entry.NameObject.FriendlyName) $($Entry.Version) $($Entry.Architecture)..."
                Get-Installer -Product $Entry.NameObject.URLName -Architecture $Entry.Architecture -Version $Entry.Version | Install-Uninstall -Procedure 'Uninstall'
                $ChangesMade = $true
            }
        } else {
            write-host ' - No matching products to remove.'
        }
    } else {
        write-host ' - No products installed.'
    }
} elseif ($Requested.Procedure -eq 'Uninstall all') {
    Write-Host 'Uninstalling products:'
    # Loop through installed products and remove each one
    if ($InstalledDotnetInstances) {
        foreach ($prod in $InstalledDotnetInstances) {
            write-host " - Removing $($prod.NameObject.FriendlyName) $($prod.Channel) $($prod.Architecture)..."
            Get-Installer -Product $prod.NameObject.URLName -Architecture $prod.Architecture -Version $prod.Version | Install-Uninstall -Procedure 'Uninstall'
            $ChangesMade = $true
        }
    } else {write-host ' - No products installed.'}
}

if ($Requested.RemoveEOLVersions) {
    $InstalledDotnetInstances = Get-InstalledInstances

    Write-Host "`r`nEnd-of-life removal:"

    if ($InstalledDotnetInstances) {
        $Removals = Find-EolDates -InstalledProducts $InstalledDotnetInstances
        foreach ($Entry in $Removals) {
            write-host " - Removing $($Entry.NameObject.FriendlyName) $($Entry.Channel) $($Entry.Architecture)..."
            Find-DownloadURL -InstallObject $Entry | Get-Installer | Install-Uninstall -Procedure 'Uninstall'
            $changesMade = $true
        }
    } else {
        write-host ' - No EOL products installed.'
    }
}

if ($ChangesMade) {
    write-host "`r`nInstalled products after changes:"
    $InstalledDotnetInstances = Get-InstalledInstances -PrintToScreen
}

if (($InstalledDotnetInstances) -and ($Requested.Procedure -ne 'Audit EOL dates')) {
    write-host "`r`nEnd-of-life audit:"
    Find-EolDates -InstalledProducts $InstalledDotnetInstances -PrintToScreen | Out-Null
}

if (-not $ChangesMade) {
    Write-Host "`r`nExiting with no changes made."
}