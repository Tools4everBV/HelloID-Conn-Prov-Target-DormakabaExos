#################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Import
# PowerShell V2
#################################################

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

#region functions
function Get-AuthorizationHeaders {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Username,

        [Parameter(Mandatory)]
        [string]
        $Password,

        [Parameter(Mandatory)]
        [string]
        $BaseUrl,

        [Parameter(Mandatory)]
        [string]
        $TenantId,

        [Parameter(Mandatory)]
        [string]
        $RequestChannel
    )
    try {
        Write-Verbose  'Get Identifier'
        $body = @{
            tenantId       = $TenantId
            requestChannel = $RequestChannel
            userName       = $Username
            password       = $Password
        }

        $splatRestMethod = @{
            Uri         = "$BaseUrl/ExosAuth/api/v1/login"
            ContentType = "application/json"
            Method      = 'POST'
            Body        = $body | ConvertTo-Json
            Verbose     = $false
        }
        $identifier = Invoke-RestMethod @splatRestMethod

        Write-Verbose 'Set Authorization Headers'
        $pair = "MyApiKey:$identifier"
        $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
        Write-Output @{
            Authorization  = "Basic $encodedCreds"
            'Content-Type' = 'application/json;charset=utf-8'
            Accept         = 'application/json;charset=utf-8'
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}

function Resolve-DormakabaExosError {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object]
        $ErrorObject
    )
    process {
        $httpErrorObj = [PSCustomObject]@{
            ScriptLineNumber = $ErrorObject.InvocationInfo.ScriptLineNumber
            Line             = $ErrorObject.InvocationInfo.Line
            ErrorDetails     = $ErrorObject.Exception.Message
            FriendlyMessage  = $ErrorObject.Exception.Message
        }
        if (-not [string]::IsNullOrEmpty($ErrorObject.ErrorDetails.Message)) {
            $httpErrorObj.ErrorDetails = $ErrorObject.ErrorDetails.Message
        }
        elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
            if ($null -ne $ErrorObject.Exception.Response) {
                $streamReaderResponse = [System.IO.StreamReader]::new($ErrorObject.Exception.Response.GetResponseStream()).ReadToEnd()
                if (-not [string]::IsNullOrEmpty($streamReaderResponse)) {
                    $httpErrorObj.ErrorDetails = $streamReaderResponse
                }
            }
        }
        try {
            $errorDetailsObject = ($httpErrorObj.ErrorDetails | ConvertFrom-Json)
            # Make sure to inspect the error result object and add only the error message as a FriendlyMessage.
            # $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    Write-Information 'Starting DormakabaExos account entitlement import'
    
    $splatAuthHeaders = @{
        Username       = $actionContext.Configuration.UserName
        Password       = $actionContext.Configuration.Password
        BaseUrl        = $actionContext.Configuration.BaseUrl
        TenantId       = $actionContext.Configuration.TenantId
        RequestChannel = $actionContext.Configuration.RequestChannel
    }

    $authorizationHeaders = Get-AuthorizationHeaders @splatAuthHeaders

    $pageSize = 100
    $pageNumber = 0
    do {
        $splatImportAccountParams = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons?skip=$($pageNumber)&top=$($pageSize)&`$expand=PersonBaseData,PersonBaseData(`$expand=PersonLoginData(`$select=*)),PersonAccessControlData,PersonTenantFreeFields"
            Method  = 'GET'
            Headers = $authorizationHeaders
        }

        $response = Invoke-RestMethod @splatImportAccountParams
        # Write-Information $($response | ConvertTo-Json)
        if ($null -ne $response.value -and $response.value.Count -gt 0) {
            foreach ($importedAccount in $response.value) {
                if ($null -eq $importedAccount.PersonBaseData) {
                    Write-Warning "Skipping account with missing PersonBaseData"
                    continue
                }

                # Make sure the displayName has a value
                $displayName = "$($importedAccount.PersonBaseData.firstName) $($importedAccount.PersonBaseData.lastName)".trim()
                if ([string]::IsNullOrEmpty($displayName)) {
                    $displayName = $importedAccount.PersonBaseData.PersonalNumber
                }

                # Make sure the userName has a value
                $username = "$($importedAccount.PersonBaseData.PersonLoginData.userName)"
                if ([string]::IsNullOrWhiteSpace($importedAccount.PersonBaseData.PersonLoginData.userName)) {
                    if ([string]::IsNullOrWhiteSpace($importedAccount.PersonBaseData.PersonalNumber)) {
                        $username = "$($importedAccount.PersonBaseData.PersonId)"
                    }
                    else {
                        $username = "$($importedAccount.PersonBaseData.PersonalNumber)"
                    }
                }

                if ($importedAccount.PersonTenantFreeFields.Text50 -eq 'Deleted by HelloID ') {
                    Write-Warning "Account [$($importedAccount.PersonBaseData.PersonId)] is 'Deleted by HelloID '. Skipping import of this account."
                    continue
                }
                Write-Output @{
                    AccountReference = $importedAccount.PersonBaseData.PersonId
                    DisplayName      = $displayName
                    UserName         = $username
                    Enabled          = -not $importedAccount.PersonAccessControlData.isBlocked
                    Data             = $importedAccount
                }
            }
        }
        $pageNumber = $pageNumber + $pageSize
    } while ($pageSize -eq $response.value.Count )

    Write-Information 'DormakabaExos account entitlement import completed'
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-DormakabaExosError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
        Write-Error "Could not import DormakabaExos account entitlements. Error: $($errorObj.FriendlyMessage)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
        Write-Error "Could not import DormakabaExos account entitlements. Error: $($ex.Exception.Message)"
    }
}
finally {
    if ($null -ne $authorizationHeaders) {
        Write-Information 'logout'

        $splatLogOut = @{
            Uri         = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/logins/logoutMyself"
            Method      = 'POST'
            Headers     = $authorizationHeaders
            Verbose     = $false
        }

        try {
            $null = Invoke-RestMethod @splatLogOut
            Write-Information "LogoutMyself succeeded"
        }
        catch {
            Write-Information "Warning LogoutMyself failed, $($_.Exception.Message) $($_.ErrorDetails.message)".trim(' ')
        }
    }
}