<#
  .SYNOPSIS
  Exports details for a given child organization under a parent MSP Duo account.
  The child's hostname must be known and provided to the script.

  .DESCRIPTION
  The script accesses the child organization's Duo account via the parent MSP's
  Accounts API, or the MSP parent's account via its Admin API. Details about
  configured users, admins, etc. are retrieved, and PDF reports are saved in a
  subfolder of the path provided to the script.

  .PARAMETER DuoAccountHostname
  Specifies the hex ID part of the child account's Duo API hostname. This is the
  value saved in ARP for the client's #DUOAccountHostname# custom variable.

  .PARAMETER OutputPath
  Specifies the base path for all of the client's reports. The script will
  create subfolders here for the product (Duo Security), year and month.

  .INPUTS
  None.

  .OUTPUTS
  None.

  .EXAMPLE
  PS> .\duo-reporting.ps1 -DuoAccountHostname "abcdef12" -OutputPath "//0.0.0.0/client-name"
#>

param(
    [Parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        $DuoAccountHostname,
        
    [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
        [ValidateNotNull()]
        $OutputPath
)

<# Exit codes:
  - 404: DuoAccountHostname doesn't exist in tenant
  - 418: No DuoAccountHostname argument received, refuse to run
#>

# Enter your Accounts API credentials. The Accounts API needs to be configured at the root MSP account
# level and has "Admin API" access to the child accounts beneath it
$Duo_ikey = ''
$Duo_skey = ''
$Duo_host = ''

# Enter your Admin API credentials. The Admin API needs to be configured at the root MSP account level
# because the Accounts API can't access the parent account the same way it can access the children
$Parent_ikey = ''
$Parent_skey = ''
$Parent_host = ''

# Report output details
$OutputBaseFolder = $OutputPath
$ReportHeaderImage = 'https://yourdomain.com/images/header_logo.png'

# This function is yanked from https://community.cisco.com/t5/apis/powershell-api-authorization-encoding/m-p/4877870
function New-DuoRequest(){
    param(
        [Parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            $apiHost,
        
        [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            [ValidateNotNull()]
            $apiEndpoint,
        
        [Parameter(ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            $apiKey,
        
        [Parameter(Mandatory=$true,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            [ValidateNotNull()]
            $apiSecret,
        
        [Parameter(Mandatory=$false,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            [ValidateNotNull()]
            $requestMethod = 'GET',
        
        [Parameter(Mandatory=$false,ValueFromPipeline=$True,ValueFromPipelineByPropertyName=$True)]
            [ValidateNotNull()]
            [System.Collections.Hashtable]$requestParams
    )
    $date = (Get-Date).ToUniversalTime().ToString("ddd, dd MMM yyyy HH:mm:ss -0000")
    $formattedParams = ($requestParams.Keys | Sort-Object | ForEach-Object {$_ + "=" + [uri]::EscapeDataString($requestParams.$_)}) -join "&"
    
    #DUO Params formatted and stored as bytes with StringAPIParams
    $requestToSign = (@(
        $Date.Trim(),
        $requestMethod.ToUpper().Trim(),
        $apiHost.ToLower().Trim(),
        $apiEndpoint.Trim(),
        $formattedParams
    ).trim() -join "`n").ToCharArray().ToByte([System.IFormatProvider]$UTF8)
 
    $hmacsha1 = [System.Security.Cryptography.HMACSHA1]::new($apiSecret.ToCharArray().ToByte([System.IFormatProvider]$UTF8))
    $hmacsha1.ComputeHash($requestToSign) | Out-Null
    $authSignature = [System.BitConverter]::ToString($hmacsha1.Hash).Replace("-", "").ToLower()

    $authHeader = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(('{0}:{1}' -f $apiKey, $authSignature)))

    $httpRequest = @{
        URI         = ('https://{0}{1}' -f $apiHost, $apiEndpoint)
        Headers     = @{
            "X-Duo-Date"    = $Date
            "Authorization" = "Basic $authHeader"
        }
        Body = $requestParams
        Method      = $requestMethod
        ContentType = 'application/x-www-form-urlencoded'
    }

    return $httpRequest
}

# Convert a DateTime object to the Unix representation, assuming a local time was provided
function ConvertTo-UnixTime() {
    param ([DateTime]$LocalTime)

    [DateTime]$UTCConversion = $LocalTime.ToUniversalTime()
    [int64]$UnixTime = Get-Date($UTCConversion) -UFormat %s

    return $UnixTime
}

# Convert Unix time object to a DateTime object and provide the local time representation
function ConvertFrom-UnixTime() {
    param ([int64]$UnixTime)

    [DateTime]$EpochStart = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0, Utc

    [DateTime]$UTCConversion = $EpochStart.AddSeconds($UnixTime)
    [DateTime]$StandardTime = $UTCConversion.ToLocalTime()

    return $StandardTime
}


# Return the Unix time representation of midnight on the first day of last month
function Get-UnixStartDate() {
    param ($Output = 'seconds')

    [DateTime]$now = Get-Date

    [DateTime]$LastMonth = $now.Date.AddMonths(-1).AddDays(-($now.day -1))
    [int64]$UnixTime = ConvertTo-UnixTime $LastMonth

    if ($Output -match "^milliseconds") {
        return [int64]$([DateTimeOffset]::FromUnixTimeSeconds($UnixTime).toUnixTimeMilliseconds())
    } else {
        return $UnixTime
    }
}

# Return the Unix time representation of midnight on the first day of last month
function Get-UnixEndDate() {
    param ($Output = 'seconds')

    [DateTime]$now = Get-Date

    [DateTime]$EndOfLastMonth = $now.Date.AddDays(-($now.day -1)).AddMilliseconds(-1)
    [int64]$UnixTime = ConvertTo-UnixTime $EndOfLastMonth

    if ($Output -match "^milliseconds") {
        return [int64]$([DateTimeOffset]::FromUnixTimeSeconds($UnixTime).toUnixTimeMilliseconds())
    } else {
        return $UnixTime
    }
}

# Get a current list of all sub-accounts' names, account_ids, and api_hostnames
function Get-ChildAccounts() {
    $values = @{
        apiHost = $Duo_host
        apiEndpoint     = '/accounts/v1/account/list'
        requestMethod   = 'POST'
        requestParams   = @{}
        apiSecret       = $Duo_skey
        apiKey          = $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

# Get an organizations's list of apps configured for use with Duo
function Get-Integrations() {
    param (
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $i_key = $parent_ikey
        $s_key = $parent_skey
        $req_params = @{}
    } else {
        $i_key = $Duo_ikey
        $s_key = $Duo_skey
        $req_params = @{account_id=$ch_acct}
    }

    $values = @{
        apiHost = $parent_host
        apiEndpoint     = '/admin/v1/integrations'
        requestMethod   = 'GET'
        requestParams   = $req_params
        apiSecret       = $s_key
        apiKey          = $i_key
    }

    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

# Get all users in an organization's tenant
function Get-Users() {
    param (
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $i_key = $parent_ikey
        $s_key = $parent_skey
        $req_params = @{
            limit=300}
    } else {
        $i_key = $Duo_ikey
        $s_key = $Duo_skey
        $req_params = @{
            account_id=$ch_acct
            limit=300}
    }

    $values = @{
        apiHost = $parent_host
        apiEndpoint     = '/admin/v1/users'
        requestMethod   = 'GET'
        requestParams   = $req_params
        apiSecret       = $s_key
        apiKey          = $i_key
    }

    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

# Get actions taken by users from a given start date in milliseconds for API v2
function Get-UserActions() {
    param (
        $milli_start,
        $milli_end,
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $i_key = $parent_ikey
        $s_key = $parent_skey
        $req_params = @{
            mintime=$milli_start
            maxtime=$milli_end
        }
    } else {
        $i_key = $Duo_ikey
        $s_key = $Duo_skey
        $req_params = @{
            account_id=$ch_acct
            mintime=$milli_start
            maxtime=$milli_end
        }
    }

    $values = @{
        apiHost = $ch_host
        apiEndpoint     = '/admin/v2/logs/authentication'
        requestMethod   = 'GET'
        requestParams   = $req_params
        apiSecret       = $s_key
        apiKey          = $i_key
    }
    
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

# Get all admins in an organization's tenant
function Get-Admins() {
    param (
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $i_key = $parent_ikey
        $s_key = $parent_skey
        $req_params = @{
            mintime=$unix_start
        }
    } else {
        $i_key = $Duo_ikey
        $s_key = $Duo_skey
        $req_params = @{
            account_id=$ch_acct
            mintime=$unix_start
        }
    }

    $values = @{
        apiHost = $parent_host
        apiEndpoint     = '/admin/v1/admins'
        requestMethod   = 'GET'
        requestParams   = $req_params
        apiSecret       = $s_key
        apiKey          = $i_key
    }

    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

# Get actions taken by admins from a given start date
function Get-AdminActions() {
    param (
        $unix_start,
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $i_key = $parent_ikey
        $s_key = $parent_skey
        $req_params = @{
            mintime=$unix_start
        }
    } else {
        $i_key = $Duo_ikey
        $s_key = $Duo_skey
        $req_params = @{
            account_id=$ch_acct
            mintime=$unix_start
        }
    }

    $values = @{
        apiHost = $ch_host
        apiEndpoint     = '/admin/v1/logs/administrator'
        requestMethod   = 'GET'
        requestParams   = $req_params
        apiSecret       = $s_key
        apiKey          = $i_key
    }
    
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}

function Export-PDFReport() {
    param (
        $rpt_title,
        $data_object,
        $tgt_folder
    )
    $source_URI = (("file://$tgt_folder/$rpt_title.html").Replace(' ','%20')).replace('\','/')

    $htm_header = @'
        <style>
            IMG {padding: 0px 0px 0px 0px; position: absolute; top: 8px; right: 16px; display: block;}
            H1 {margin-top: 20px; margin-right: 170px; margin-bottom:15px; font-size: 23px;}
            TABLE {width: 100%; border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse; font-size: 11px}
            TH {background-color: #6bbf4e; border-bottom: 1px solid #000000; text-align: left;}
            TD {border-bottom: 1px solid #000000;}
            TR:nth-child(odd) {background-color: #d2d2d2;}
            TABLE, H1, H3 {font-family: Arial, Helvetica, sans-serif; font-weight: 200;}
        </style>
'@

    $rpt_header = @"
        <img src="$ReportHeaderImage" width=160 height=50 />
        <h1>$rpt_title</h1>
"@

    if ($null -eq $data_object) {
        ($data_object | ConvertTo-Html -title $rpt_title -precontent $rpt_header -Head $htm_header -postcontent "<h3>No data available</h3>" `
                            | Out-String).Replace("<table>.+</table>","") `
                                    | Out-File "$tgt_folder\$rpt_title.html"
    } else {
        $data_object | ConvertTo-Html -title $rpt_title -precontent $rpt_header -Head $htm_header `
                        | Out-File "$tgt_folder\$rpt_title.html"
    }

    $edge_args = @(
        '--headless',
        "--print-to-pdf=""$tgt_folder\$rpt_title.pdf""",
        '--disable-extensions',
        '--no-pdf-header-footer',
        '--disable-popup-blocking',
        '--run-all-compositor-stages-before-draw',
        '--disable-checker-imaging',
        "$source_URI"
    )

    Start-Process 'msedge.exe' -ArgumentList $edge_args -Wait
    Remove-item -path "$tgt_folder\$rpt_title.html" -force
}

#################################
#   Execution   begins   here   #
#################################

# Determine whether we need to run at all
if ($null -eq $DuoAccountHostname) {
    Write-Error 'No DuoAccountHostname received (#DUOAccountHostname# value is missing in ARP).'
    exit 418
} else {
    # Assemble the API hostname if we did receive a value
    $child_host = "api-$DuoAccountHostname.duosecurity.com"
}

# Find out what organizations we have as children under our parent MSP account
$child_accts = Get-ChildAccounts

# Create an additional entry for the sub account list
$parent_acct = [PSCustomObject]@{
    account_id = $Parent_ikey
    api_hostname = $Parent_host
    name = 'MSP Parent Account'
}

# Declare a new/empty mutable collection of accounts
$all_accts = New-Object System.Collections.ArrayList

# Add all the accounts we know about
foreach ($acct in $child_accts) {$all_accts.add($acct)}
$all_accts.add($parent_acct)

# Check whether we received a valid hostname
$child_acct_id = $null
$child_acct_name = $null
ForEach ($org in $all_accts) {
    if ($org.api_hostname -eq $child_host) {
        $child_acct_id = $org.account_id
        $child_acct_name = (($org.name).replace(':',' ').replace('\',' ').replace('/',' ').replace('?',' ').replace('*',' ').replace('"',' ').replace('<',' ').replace('>',' ').replace('|',' ').replace('  ',' ')).trim('.')
        break
    }
}

# Quit if the hostname provided doesn't match any child accounts
if ($null -eq $child_acct_id) {
    Write-Error 'DuoAccountHostname provided does not exist in tenant (#DUOAccountHostname# value is wrong in ARP).'
    exit 404
}

# Get the start and end times for the logs we want to see
$LogsStart = Get-UnixStartDate
# $LogsEnd = Get-UnixEndDate
$LogsStartMilliseconds = Get-UnixStartDate 'milliseconds'
$LogsEndMilliseconds = Get-UnixEndDate 'milliseconds'

# Convert to DateTime for creating report subfolders
$ReportDate = ConvertFrom-UnixTime $LogsStart

# Find/create an output folder for the org we're looking at
$targetFolder = "$OutputBaseFolder\Duo Security\$(get-date($reportdate) -uformat %Y)\$(get-date($reportdate) -uformat %B)"
if ($false -eq (test-path $targetFolder)) {
    New-Item -ItemType Directory -path $targetFolder | out-null
}

# Get all integrations
$integrations = Get-Integrations $child_acct_id $child_host

# Get all users in the tenant
$users = Get-Users $child_acct_id $child_host

# Get all user actions within date contstraints
$userActions = Get-UserActions $LogsStartMilliseconds $LogsEndMilliseconds $child_acct_id $child_host

# Get list of all admins
$admins = Get-Admins $child_acct_id $child_host

# Get all admin actions from date
$adminActions = Get-AdminActions $LogsStart $child_acct_id $child_host

# Report on just the integrations' properties we're interested in
$reportTitle = "$child_acct_name - Duo Integrations"
$integrationsFormatted = $integrations | Sort-Object -Property name `
                            | Select-Object @{Label="Name"; Expression={$_.name}}, `
                                @{Label='Type'; Expression={$_.type}}
Export-PDFReport $reportTitle $integrationsFormatted $targetFolder

# Report on just the users' properties we're interested in
$reportTitle = "$child_acct_name - Duo Users"
$usersFormatted = $users | Sort-Object -Property username `
                    | Select-Object @{Label='Name'; Expression={$_.realname}}, `
                        @{Label='Username'; Expression={$_.username}}, `
                        @{Label='Email Address'; Expression={$_.email}}, `
                        @{Label='Status'; Expression={$_.status}}, `
                        @{Label='Last Login'; Expression={if ($null -ne $_.last_login) {ConvertFrom-UnixTime $_.last_login} else {'Never'}}}
Export-PDFReport $reportTitle $usersFormatted $targetFolder

# Report on user actions
$reportTitle = "$child_acct_name - Duo User Activity"
$userActionsFormatted = $userActions | Select-Object -ExpandProperty authlogs `
                                        | Select-Object @{Label='Timestamp'; Expression={(get-date $_.isotimestamp).ToLocalTime()}}, `
                                            @{Label='User'; Expression={$_.user.name}}, `
                                            @{Label='Application'; Expression={$_.application.name}}, `
                                            @{Label='Result'; Expression={$_.result}}, `
                                            @{Label='Reason'; Expression={if ($_.reason -eq 'allow_unenrolled_user_on_trusted_network') {'trusted_network'} else {$_.reason}}}, `
                                            @{Label='IP Address'; Expression={$_.access_device.ip}} `
                                                | Sort-Object -Property @{Expression='Timestamp'; Descending = $false}
Export-PDFReport $reportTitle $userActionsFormatted $targetFolder

# Report on admins' properties we're interested in
$reportTitle = "$child_acct_name - Duo Administrators"
$adminsFormatted = $admins | Sort-Object -Property name `
                    | Select-Object @{Label='Name'; Expression={$_.name}}, `
                        @{Label='Email Address'; Expression={$_.email}}, `
                        @{Label='Role'; Expression={$_.role}}, `
                        @{Label='Status'; Expression={$_.status}}, `
                        @{Label='Last Login'; Expression={if ($null -ne $_.last_login) {ConvertFrom-UnixTime $_.last_login} else {'Never'}}}
Export-PDFReport $reportTitle $adminsFormatted $targetFolder

# Report on admin actions
$reportTitle = "$child_acct_name - Duo Administrator Activity"
$AdminActionsFormatted = $adminActions | where-object  {(($_.username -ne 'System') `
                                            -and ($_.username -notmatch "API \(.*\)") `
                                            -and ($_.username -notmatch "Microsoft Entra ID") `
                                            -and ($_.username -notmatch "AD User Sync"))} `
                                                | Select-Object @{Label='Timestamp'; Expression={(get-date $_.isotimestamp).ToLocalTime()}}, `
                                                    @{Label='User'; Expression={$_.username}}, `
                                                    @{Label='Action'; Expression={$_.action}}, `
                                                    @{Label='Target'; Expression={$_.object}}, `
                                                    @{Label='Description'; Expression={$_.description}}
Export-PDFReport $reportTitle $AdminActionsFormatted $targetFolder