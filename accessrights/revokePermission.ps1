#################################################################
# HelloID-Conn-Prov-Target-DormakabaExos-RevokePermission-AccessRight
# PowerShell V2
#################################################################

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
            $httpErrorObj.FriendlyMessage = $errorDetailsObject.message
            # $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails # Temporarily assignment
        }
        catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

# Begin
try {
    # Verify if [accountReference] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }
$actionContext.DryRun = $false
    Write-Information 'Verifying if a DormakabaExos account exists'

    $splatAuthHeaders = @{
        Username       = $actionContext.Configuration.UserName
        Password       = $actionContext.Configuration.Password
        BaseUrl        = $actionContext.Configuration.BaseUrl
        TenantId       = $actionContext.Configuration.TenantId
        RequestChannel = $actionContext.Configuration.RequestChannel
    }

    $authorizationHeaders = Get-AuthorizationHeaders @splatAuthHeaders

    $correlationValue = $actionContext.References.Account
    $splatGetPersons = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonId eq '$correlationValue')&`$expand=PersonBaseData(`$select=*)"
        Method  = 'GET'
        Headers = $authorizationHeaders
    }
    $correlatedAccount = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]
    if ($null -ne $correlatedAccount) {
        $lifecycleProcess = 'RevokePermission'
    }
    else {
        $lifecycleProcess = 'NotFound'
    }

    # Process
    switch ($lifecycleProcess) {
        'RevokePermission' {

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Revoking DormakabaExos permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)]"

                $splatRevokeAccessRight = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.1/persons/$($correlatedAccount.PersonBaseData.PersonId)/unassignAccessRight"
                    Method  = 'POST'
                    Headers = $authorizationHeaders
                    Body    = @{ 
                                AccessRightId = "$($actionContext.References.Permission.Reference)" 
                                # ValidFrom     = (Get-Date -Format 'yyyy-MM-dd').ToString()
                                } | ConvertTo-Json -Depth 10
                }

                $null = (Invoke-RestMethod @splatRevokeAccessRight -Verbose:$false).value
            }
            else {
                Write-Information "[DryRun] Revoke DormakabaExos permission: [$($actionContext.PermissionDisplayName)] - [$($actionContext.References.Permission.Reference)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "Revoke DormakabaExos permission: [$($actionContext.PermissionDisplayName)] from [$($actionContext.References.Account)] was successful. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "DormakabaExos account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "DormakabaExos account: [$($actionContext.References.Account)] could not be found, indicating that it may have been deleted. Action initiated by: [$($actionContext.Origin)]"
                    IsError = $false
                })
            break
        }
    }
}
catch {
    $outputContext.Success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-DormakabaExosError -ErrorObject $ex
        $auditLogMessage = "Could not revoke DormakabaExos permission for account: [$($actionContext.References.Account)]. Error: $($errorObj.FriendlyMessage). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        $auditLogMessage = "Could not revoke DormakabaExos permission for account: [$($actionContext.References.Account)]. Error: $($ex.Exception.Message). Action initiated by: [$($actionContext.Origin)]"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    if ($auditLogMessage -like "*An access right with the given key and the defined validity period is not assigned to the person*") {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $false
        })
        $outputContext.Success = $true
    }
    else {
        $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditLogMessage
            IsError = $true
        })
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