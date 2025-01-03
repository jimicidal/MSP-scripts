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

# Enter the folder where the csv will be created
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


# Find out what organizations we have as children under our parent MSP account
$child_accts = Get-ChildAccounts

# Create an additional entry for the sub account list
$parent_acct = [PSCustomObject]@{
    account_id = $Parent_ikey
    api_hostname = $Parent_host
    name = "MSP Parent Account"
}

# Declare a mutable collection of accounts to loop through
$all_accts = New-Object System.Collections.ArrayList

# Start adding items
foreach ($acct in $child_accts) {$all_accts.add($acct)}
$all_accts.add($parent_acct)

# Declare a mutable collection of users
$all_users = New-Object System.Collections.ArrayList

# Loop through all child orgs and get integrations/users/etc. details
ForEach ($org in $all_accts) {
    $child_acct_name = (($org.name).replace(':','').replace('\','').replace('/','').replace('?','').replace('*','').replace('"','').replace('<','').replace('>','').replace('|','')).trim('.')
    $child_acct_id = $org.account_id
    $child_host = $org.api_hostname

    # Find/create an output folder for the org we're looking at
    if ($false -eq (test-path $OutputFolder)) {
        New-Item -ItemType Directory -path $OutputFolder | out-null
    }

    # Get users in the tenant
    $users = Get-Users $child_acct_id $child_host

    # Display the users
    $usersFormatted = $users | Sort-Object -Property username `
                        | Select-Object @{Label="Organization"; Expression={$child_acct_name}}, `
                            @{Label="Username"; Expression={$_.username}}, `
                            @{Label="Name"; Expression={$_.realname}}, `
                            @{Label="Email Address"; Expression={$_.email}}, `
                            @{Label="Status"; Expression={$_.status}}, `
                            @{Label="Last Login"; Expression={if ($null -ne $_.last_login) {ConvertFrom-UnixTime $_.last_login} else {"Never"}}}
    foreach ($uf in $usersFormatted) {$all_users.Add($uf)}
}
$all_users | select-object Organization,Username,Name,"Email Address",Status,"Last Login" | Export-Csv -Path "$OutputFolder\DuoUsers.csv" -NoTypeInformation