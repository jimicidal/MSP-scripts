function New-DuoRequest() {
    #From https://community.cisco.com/t5/apis/powershell-api-authorization-encoding/m-p/4877870
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
    #Duo Params formatted and stored as bytes with StringAPIParams
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
        URI         =   ('https://{0}{1}' -f $apiHost, $apiEndpoint)
        Headers     =   @{
            "X-Duo-Date"    =   $Date
            "Authorization" =   "Basic $authHeader"
        }
        Body        =   $requestParams
        Method      =   $requestMethod
        ContentType =   'application/x-www-form-urlencoded'
    }
    $httpRequest
}

function Get-ChildAccounts() {
    ####Get list of child accounts
    $values = @{
        apiHost         =   $Duo_host
        apiEndpoint     =   '/accounts/v1/account/list'
        requestMethod   =   'POST'
        requestParams   =   @{}
        apiSecret       =   $Duo_skey
        apiKey          =   $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest
    $child_accts = ($wr.Content | ConvertFrom-Json).response
    return $child_accts
}

function Get-ChildIntegrations() {
    ####Get a child account's integrations
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
            [string]$child_acct_id,
        [Parameter(Mandatory)]
            [string]$child_host
    )
    $values = @{
        apiHost = $child_host
        apiEndpoint     =   '/admin/v1/integrations'
        requestMethod   = 'GET'
        requestParams   = @{account_id=$child_acct_id}
        apiSecret       = $Duo_skey
        apiKey          =   $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values
    $wr = Invoke-WebRequest @contructWebRequest
    $child_integrations = (($wr.Content | ConvertFrom-Json).response | Select-Object name,type)
    return $child_integrations
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName PresentationFramework #For message boxes

$lblChildOrgs = New-Object system.Windows.Forms.Label
$lblChildOrgs.Text = "Select an organization"
$lblChildOrgs.AutoSize = $true
$lblChildOrgs.Location = New-Object Drawing.Point(10,10)

$cboChildOrgs = New-Object system.Windows.Forms.ComboBox
$cboChildOrgs.text = ""
$cboChildOrgs.width = 300
$cboChildOrgs.autosize = $true
$cboChildOrgs.location = New-Object System.Drawing.Point(10,30)
$arrChildOrgs = Get-ChildAccounts
$arrChildOrgs | ForEach-Object {[void] $cboChildOrgs.Items.Add($_.name)}

$btnGetIntegrations = New-Object System.Windows.Forms.Button
$btnGetIntegrations.Location = New-Object System.Drawing.Size (10,60)
$btnGetIntegrations.Size = New-Object System.Drawing.Size(160,30)
$btnGetIntegrations.Text = "Get Integrations"
$btnGetIntegrations.Add_Click({
    $org = $cboChildOrgs.text
    $i = [array]::indexof($arrChildOrgs.name,$org)
    $acct = ($arrChildOrgs[$i].account_id | out-string).trim()
    $hostn = ($arrChildOrgs[$i].api_hostname | out-string).trim()
    $arrChildIntegrations = Get-ChildIntegrations $acct $hostn
    [System.Windows.MessageBox]::Show(($arrChildIntegrations | out-string))
})

$btnGetUsers = New-Object System.Windows.Forms.Button
$btnGetUsers.Location = New-Object System.Drawing.Size (180,60)
$btnGetUsers.Size = New-Object System.Drawing.Size(160,30)
$btnGetUsers.Text = "Get Users"
$btnGetUsers.Add_Click({
    $org = $cboChildOrgs.text
    $i = [array]::indexof($arrChildOrgs.name,$org)
    $acct = ($arrChildOrgs[$i].account_id | out-string).trim()
    $hostn = ($arrChildOrgs[$i].api_hostname | out-string).trim()
    $arrChildIntegrations = Get-ChildIntegrations $acct $hostn
    [System.Windows.MessageBox]::Show(($arrChildIntegrations | out-string))
})

$btnGetAdminActions = New-Object System.Windows.Forms.Button
$btnGetAdminActions.Location = New-Object System.Drawing.Size (350,60)
$btnGetAdminActions.Size = New-Object System.Drawing.Size(160,30)
$btnGetAdminActions.Text = "Get Admin Actions"
$btnGetAdminActions.Add_Click({
    $org = $cboChildOrgs.text
    $i = [array]::indexof($arrChildOrgs.name,$org)
    $acct = ($arrChildOrgs[$i].account_id | out-string).trim()
    $hostn = ($arrChildOrgs[$i].api_hostname | out-string).trim()
    $arrChildIntegrations = Get-ChildIntegrations $acct $hostn
    [System.Windows.MessageBox]::Show(($arrChildIntegrations | out-string))
})


$frmDuo = New-Object Windows.Forms.Form
$frmDuo.Text = "Duo"
$frmDuo.Width = 550
$frmDuo.Height = 350

$frmDuo.Controls.add($cboChildOrgs)
$frmDuo.Controls.add($lblChildOrgs)
$frmDuo.Controls.add($btnGetIntegrations)
$frmDuo.Controls.add($btnGetUsers)
$frmDuo.Controls.add($btnGetAdminActions)
$frmDuo.Add_Shown({$frmDuo.Activate()})
$frmDuo.ShowDialog()




## HELPFUL:
##### https://www.itprotoday.com/powershell/tips-developing-powershell-gui-examples
##### https://www.techtarget.com/searchitoperations/tutorial/Boost-productivity-with-these-PowerShell-GUI-examples  



###################### List Child Accounts ######################
# Get a current list of all sub-accounts' names, account_ids, and api_hostnames
# This request goes straight to the Accounts API, no Admin API involved here

write-host "###################### List Child Accounts ######################"
$values = @{
    apiHost = $Duo_host
    apiEndpoint     = '/accounts/v1/account/list'
    requestMethod   = 'POST'
    requestParams   = @{}
    apiSecret       = $Duo_skey
    apiKey          = $Duo_ikey
}
$contructWebRequest = New-DuoRequest @values

# Send the request
$wr = Invoke-WebRequest @contructWebRequest

# Save the list as an object
$child_accts = ($wr.Content | ConvertFrom-Json).response

# Display the results
$child_accts | format-table



###################### Integrations ######################
# Loop through the list of child accounts and check what apps they have configured for use with Duo
# This request goes to the child accounts' Admin APIs via the parent Accounts API, so you provide their
# account_id as a parameter with the parent ikey and skey in the header. These results would be something
# to include in the monthly report for each client

write-host "###################### Integrations ######################"
ForEach ($org in $child_accts) {
    $child_acct_name = $org.name
    $child_acct_id = $org.account_id
    $child_host = $org.api_hostname

    $values = @{
        apiHost = $child_host
        apiEndpoint     = '/admin/v1/integrations'
        requestMethod   = 'GET'
        requestParams   = @{account_id=$child_acct_id}
        apiSecret       = $Duo_skey
        apiKey          = $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values

    # Send the request
    $wr = Invoke-WebRequest @contructWebRequest

    # Save the response as an object
    $response = ($wr.Content | ConvertFrom-Json).response

    # Display the findings
    write-host `r`n$child_acct_name
    $response | format-table name,type
}



###################### Users ######################
# Get all users for each child account. The last login timestamp will need to be converted from Unix time.
# This should also be included in the monthly reporting, and also uses the child account's details
# via the parent account API

write-host "###################### Users ######################"
ForEach ($org in $child_accts) {
    $child_acct_name = $org.name
    $child_acct_id = $org.account_id
    $child_host = $org.api_hostname

    $values = @{
        apiHost = $child_host
        apiEndpoint     = '/admin/v1/users'
        requestMethod   = 'GET'
        requestParams   = @{
            account_id=$child_acct_id
            limit=300}
        apiSecret       = $Duo_skey
        apiKey          = $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values

    # Send the request
    $wr = Invoke-WebRequest @contructWebRequest

    # Save the response as an object
    $response = ($wr.Content | ConvertFrom-Json).response

    # Display the users
    write-host `r`n$child_acct_name`r`n"-------------------------------------"
    $response | Format-Table @{Label="Name"; Expression={$_.realname}}, `
            @{Label="Username"; Expression={$_.username}}, `
            @{Label="Email Address"; Expression={$_.email}}, `
            @{Label="Status"; Expression={$_.status}}, `
            @{Label="Last Login"; Expression={$_.last_login}}
}



###################### Admin actions ######################
# Get admin actions logs for all child orgs. The mintime parameter here is hard-coded, but should probably
# be the start of the previous month on each run. There is no "maxtime" parameter. This should also be included
# in the monthly reporting. It would be useful to have this info for the EOJ parent account as well, but the
# Accounts API doesn't have this info and I didn't find an account_id to add the parent account to the array.

write-host "###################### Admin actions ######################"
ForEach ($org in $child_accts) {
    $child_acct_name = $org.name
    $child_acct_id = $org.account_id
    $child_host = $org.api_hostname

    $values = @{
        apiHost = $child_host
        apiEndpoint     = '/admin/v1/logs/administrator'
        requestMethod   = 'GET'
        requestParams   = @{
            account_id=$child_acct_id
            mintime="1714539600"
        }
        apiSecret       = $Duo_skey
        apiKey          = $Duo_ikey
    }
    $contructWebRequest = New-DuoRequest @values

    # Send the request
    $wr = Invoke-WebRequest @contructWebRequest

    # Save the response as an object
    $response = ($wr.Content | ConvertFrom-Json).response

    # Display the request
    # I'm filtering out the "API (*)" usernames as they generate some noise, as well as the "Microsoft Entra
    # ID" and "AD User Sync" strings via regex (none of those strings are a complete match). "System" is
    # also filtered for the same reason, but that's an exact match
    write-host `r`n$child_acct_name`r`n"-------------------------------------"
    $response | where-object  {($_.username -ne "System" -and $_.username -notmatch "API \(.*\)" -and $_.username -notmatch "Microsoft Entra ID" -and $_.username -notmatch "AD User Sync")} `
        | Format-Table @{Label="Timestamp"; Expression={$_.isotimestamp}}, `
            @{Label="User"; Expression={$_.username}}, `
            @{Label="Action"; Expression={$_.action}}, `
            @{Label="Target"; Expression={$_.object}}, `
            @{Label="Description"; Expression={$_.description}}
            # I plopped the whole description as-is here and that's probably fine, it's just not very
            # friendly from a client's perspective. I can see them asking questions about what these mean,
            # so I intended to generate human-readable blurbs for them. The only thing is each action comes
            # with a different set of details in the description, so you would have to create a template
            # for each action type, e.g., "Logged in from {IP}" for admin_login and "Updated {field}[, {field2}...]"
            # for the user_update action
}