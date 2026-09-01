############################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Permissions-AccessRights
# PowerShell V2
############################################################

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
    Write-Information 'Retrieving permissions'
    $splatAuthHeaders = @{
        Username       = $actionContext.Configuration.UserName
        Password       = $actionContext.Configuration.Password
        BaseUrl        = $actionContext.Configuration.BaseUrl
        TenantId       = $actionContext.Configuration.TenantId
        RequestChannel = $actionContext.Configuration.RequestChannel
    }

    $authorizationHeaders = Get-AuthorizationHeaders @splatAuthHeaders

    $splatRestMethod = @{
        Uri         = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/AccessRights"
        ContentType = "application/json"
        Method      = 'GET'
        Headers     = $authorizationHeaders
        Verbose     = $false
    }

    $retrievedPermissions = (Invoke-RestMethod @splatRestMethod) 

    # Make sure to test with special characters and if needed; add utf8 encoding.
    foreach ($permission in $retrievedPermissions.Value) {
        $outputContext.Permissions.Add(
            @{
                DisplayName    = $permission.DisplayName
                Identification = @{
                    Reference = $permission.AccessRightId
                }
            }
        )
    }
}
catch {
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-DormakabaExosError -ErrorObject $ex
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    }
    else {
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
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