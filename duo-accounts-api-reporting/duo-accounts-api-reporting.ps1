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

# Enter the root folder where subdirectories for each client will be created
$OutputFolder = 'C:\Temp'


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


# Return the Unix time representation of midnight on the first day of last month. We're assuming
# that you want to see logs from the previous month until now when you run this script
function Get-StartDate() {
    [DateTime]$now = Get-Date

    [DateTime]$LastMonth = $now.Date.AddMonths(-1).AddDays(-($now.day -1))
    [int64]$UnixTime = ConvertTo-UnixTime $LastMonth

    return $UnixTime
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

    if ($ch_host -eq $Parent_host) {
        $values = @{
            apiHost = $parent_host
            apiEndpoint     = '/admin/v1/integrations'
            requestMethod   = 'GET'
            requestParams   = @{}
            apiSecret       = $parent_skey
            apiKey          = $parent_ikey
        }
    } else {
        $values = @{
            apiHost = $ch_host
            apiEndpoint     = '/admin/v1/integrations'
            requestMethod   = 'GET'
            requestParams   = @{account_id=$ch_acct}
            apiSecret       = $Duo_skey
            apiKey          = $Duo_ikey
        }
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
        $values = @{
            apiHost = $parent_host
            apiEndpoint     = '/admin/v1/users'
            requestMethod   = 'GET'
            requestParams   = @{
                limit=300}
            apiSecret       = $Parent_skey
            apiKey          = $Parent_ikey
        }
    } else {
        $values = @{
            apiHost = $ch_host
            apiEndpoint     = '/admin/v1/users'
            requestMethod   = 'GET'
            requestParams   = @{
                account_id=$ch_acct
                limit=300}
            apiSecret       = $Duo_skey
            apiKey          = $Duo_ikey
        }
    }
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}


# Get all administrators in an organization's tenant
function Get-Admins() {
    param (
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $values = @{
            apiHost = $parent_host
            apiEndpoint     = '/admin/v1/admins'
            requestMethod   = 'GET'
            requestParams   = @{
                mintime=$unix_start
            }
            apiSecret       = $Parent_skey
            apiKey          = $Parent_ikey
        }
    } else {
        $values = @{
            apiHost = $ch_host
            apiEndpoint     = '/admin/v1/admins'
            requestMethod   = 'GET'
            requestParams   = @{
                account_id=$ch_acct
                mintime=$unix_start
            }
            apiSecret       = $Duo_skey
            apiKey          = $Duo_ikey
        }
    }

    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}


# Get actions taken by admins from the given start date
function Get-AdminActions() {
    param (
        $unix_start,
        $ch_acct,
        $ch_host
    )

    if ($ch_host -eq $parent_host) {
        $values = @{
            apiHost = $parent_host
            apiEndpoint     = '/admin/v1/logs/administrator'
            requestMethod   = 'GET'
            requestParams   = @{
                mintime=$unix_start
            }
            apiSecret       = $parent_skey
            apiKey          = $parent_ikey
        }
    } else {
        $values = @{
            apiHost = $ch_host
            apiEndpoint     = '/admin/v1/logs/administrator'
            requestMethod   = 'GET'
            requestParams   = @{
                account_id=$ch_acct
                mintime=$unix_start
            }
            apiSecret       = $Duo_skey
            apiKey          = $Duo_ikey
        }
    }
    
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest

    return ($wr.Content | ConvertFrom-Json).response
}


# This function takes the massaged data and generates a web page. All your visual formatting will go
# here and become a .html file. Then MSEdge.exe exports it to PDF and the HTML files are deleted
function Export-PDFReport() {
    param (
        $rpt_title,
        $ch_acct,
        $data_object,
        $tgt_folder
    )

    # Quick conversion to URL-encoded path from the on-disk location of the report's destination
    $source_URI = (("file://$tgt_folder/$rpt_title.html").Replace(" ","%20")).replace("\","/")

    $htm_header = @"
        <style>
            IMG {position: absolute; top: 20px; right: 20px;}
            H1 {margin-top: 50px}
            TABLE {width: 100%; border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}
            TH {background-color: #6bbf4e; border-bottom: 1px solid #000000; text-align: left;}
            TD {border-bottom: 1px solid #000000}
            TR:nth-child(odd) {background-color: #d2d2d2;}
            TABLE, H1, H3 {font-family: Arial, Helvetica, sans-serif; font-weight: 200;}
        </style>
"@

    # Change this to the path of your logo or create a resources subdirectory for it in your root output dir
    $rpt_header = @"
        <img src="$OutputFolder\res\Sample Logo.png" />
        <h1>$rpt_title</h1>
"@

    if ($null -eq $data_object) {
        ($data_object | ConvertTo-Html -title $rpt_title -precontent $rpt_header -Head $htm_header -postcontent "<h3>No data available</h3>" `
                            | Out-String).Replace("<table>.*</table>","") `
                                    | Out-File "$tgt_folder\$rpt_title.html"
    } else {
        $data_object | ConvertTo-Html -title $rpt_title -precontent $rpt_header -Head $htm_header `
                        | Out-File "$tgt_folder\$rpt_title.html"
    }

    $edge_args = @(
        "--headless",
        "--print-to-pdf=""$tgt_folder\$rpt_title.pdf""",
        "--disable-extensions",
        "--print-to-pdf-no-header",
        "--disable-popup-blocking",
        "--run-all-compositor-stages-before-draw",
        "--disable-checker-imaging",
        "$source_URI"
    )
    Start-Process "msedge.exe" -ArgumentList $edge_args -Wait
    Remove-item -path "$tgt_folder\$rpt_title.html" -force
}



# Find out what organizations we have as children under our parent MSP account
$child_accts = Get-ChildAccounts

# Create an additional entry for the parent account
$parent_acct = [PSCustomObject]@{
    account_id = $Parent_ikey
    api_hostname = $Parent_host
    name = "MSP Parent Account"
}

# Declare a mutable collection of accounts to loop through
$all_accts = New-Object System.Collections.ArrayList

# Add parent and child account objects to the array
foreach ($acct in $child_accts) {$all_accts.add($acct)}
$all_accts.add($parent_acct)

# Get the start time (in Unix representation) for the earliest logs we want to see
$LogsStart = Get-StartDate

# Convert to a DateTime objectfor easy use while creating report subfolders
$ReportDate = ConvertFrom-UnixTime $LogsStart

# Initialize a hashtable to count the number of times admins place users in bypass mode.
# This becomes its own separate report and is unique to the parent MSP account
$bypassAdmins = @{}

# Loop through all orgs and get their juicy details
ForEach ($org in $all_accts) {
    $child_acct_name = (($org.name).replace(":","")).trim(".")
    $child_acct_id = $org.account_id
    $child_host = $org.api_hostname

    # Find/create an output folder for the org we're looking at. This is where you define the naming
    # of your folder structure
    $targetFolder = "$OutputFolder\$child_acct_name\Duo Security\$(get-date($reportdate) -uformat %Y)\$(get-date($reportdate) -uformat %B)"
    if ($false -eq (test-path $targetFolder)) {
        New-Item -ItemType Directory -path $targetFolder | out-null
    }

    # Get integrations for the account
    $integrations = Get-Integrations $child_acct_id $child_host

    # Get users in the tenant
    $users = Get-Users $child_acct_id $child_host

    # Get list of admins
    $admins = Get-Admins $child_acct_id $child_host

    # Get admin actions
    $adminActions = Get-AdminActions $LogsStart $child_acct_id $child_host

    # Make the integrations' headings start with a capital letter to look better
    $reportTitle = "Duo Integrations"
    $integrationsFormatted = $integrations | Sort-Object -Property name `
                                | Select-Object @{Label="Name"; Expression={$_.name}}, `
                                    @{Label="Type"; Expression={$_.type}}

    # Send the massaged data and additional details to be exported to PDF
    Export-PDFReport $reportTitle $child_acct_name $integrationsFormatted $targetFolder

    # Update the users' headings for readability
    $reportTitle = "Duo Users"
    $usersFormatted = $users | Sort-Object -Property username `
                        | Select-Object @{Label="Name"; Expression={$_.realname}}, `
                            @{Label="Username"; Expression={$_.username}}, `
                            @{Label="Email Address"; Expression={$_.email}}, `
                            @{Label="Status"; Expression={$_.status}}, `
                            @{Label="Last Login"; Expression={if ($null -ne $_.last_login) {ConvertFrom-UnixTime $_.last_login} else {"Never"}}}

    # Send the massaged data and additional details to be exported to PDF
    Export-PDFReport $reportTitle $child_acct_name $usersFormatted $targetFolder

    # Update the admins' headings similarly to the users' headings above
    $reportTitle = "Duo Administrators"
    $adminsFormatted = $admins | Sort-Object -Property name `
                        | Select-Object @{Label="Name"; Expression={$_.name}}, `
                            @{Label="Email Address"; Expression={$_.email}}, `
                            @{Label="Role"; Expression={$_.role}}, `
                            @{Label="Status"; Expression={$_.status}}, `
                            @{Label="Last Login"; Expression={if ($null -ne $_.last_login) {ConvertFrom-UnixTime $_.last_login} else {"Never"}}}

    # Send the massaged data and additional details to be exported to PDF
    Export-PDFReport $reportTitle $child_acct_name $adminsFormatted $targetFolder

    # Check for admin bypass usage - instances where a Duo admin has put a user in bypass mode. We want to know
    # if anybody is abusing this feature as it can be easy to forget to put the user back into active status,
    # thereby leaving gaps in your security. Opt for bypass codes instead!
    $bypassEvents = $adminActions | where-object  {(($_.description -match [regex]::escape('"status": "Bypass"')) `
                                                -and ($_.action -eq "user_update") `
                                                -and ($_.username -ne "System") `
                                                -and ($_.username -notmatch "API \(.*\)") `
                                                -and ($_.username -notmatch "Microsoft Entra ID") `
                                                -and ($_.username -notmatch "AD User Sync"))}

    # Update running total of bypass events overall per all admins, outside of just this organization. We're only
    # counting the number of events per admin, not breaking down by subaccount, user, etc.
    foreach ($event in $bypassEvents) {
        $un = $event.username
        if ($bypassAdmins.ContainsKey($un)) {
            $bypassAdmins.$un += 1
        } else {
            $bypassAdmins.Add($un, 1)
        }
    }

    # Format the admin actions log data
    # I'm filtering out the "API (*)" usernames as they generate some noise, as well as the "Microsoft Entra
    # ID" and "AD User Sync" strings via regex (none of those strings are a complete match). "System" is
    # also filtered for the same reason, but that's an exact match. You should check whether these or other
    # usernames are even an issue in your environment. This filtering is also performed above for bypass events
    $reportTitle = "Duo Administrator Activity"
    $AdminActionsFormatted = $adminActions | where-object  {(($_.username -ne "System") `
                                                -and ($_.username -notmatch "API \(.*\)") `
                                                -and ($_.username -notmatch "Microsoft Entra ID") `
                                                -and ($_.username -notmatch "AD User Sync"))} `
                                                    | Select-Object @{Label="Timestamp"; Expression={(get-date $_.isotimestamp).ToLocalTime()}}, `
                                                        @{Label="User"; Expression={$_.username}}, `
                                                        @{Label="Action"; Expression={$_.action}}, `
                                                        @{Label="Target"; Expression={$_.object}}, `
                                                        @{Label="Description"; Expression={$_.description}}
                                                            # I plopped the whole description here as-is and that's probably fine, it's just not very
                                                            # friendly from a client's perspective. I might generate human-readable blurbs for them.
                                                            # Each action comes with a different set of details in the description, though, so you would
                                                            # have to create a template for each action type, e.g., "Logged in from {IP}" for the 
                                                            # `admin_login` action and "Updated {field}[, {field2}...]" for the `user_update` action

    # Send the massaged data and additional details to be exported to PDF
    Export-PDFReport $reportTitle $child_acct_name $AdminActionsFormatted $targetFolder
}

# Sort the bypass event count data for the final report
$reportTitle = "Total Bypass Events - All Accounts"
$bypassEventsFormatted = $bypassAdmins.GetEnumerator() `
                            | Sort-Object -Property value -Descending

# Send the massaged data and additional details to be exported to PDF
Export-PDFReport $reportTitle $parent_acct.name $bypassEventsFormatted $targetFolder