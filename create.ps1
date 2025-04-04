#################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Create
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
        $BaseUrl
    )
    try {
        Write-Verbose  'Get Identifier'
        $pair = "$($Username):$($Password)"
        $encodedCredsUsername = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
        $splatRestMethod = @{
            Uri     = "$BaseUrl/ExosApiLogin/api/v1.0/login"
            Method  = 'POST'
            Headers = @{
                Authorization = "Basic $encodedCredsUsername"
            }
        }
        $identifier = (Invoke-RestMethod @splatRestMethod -Verbose:$false).value.Identifier

        Write-Verbose 'Set Authorization Headers'
        $pair = "MyApiKey:$identifier"
        $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
        Write-Output @{
            Authorization  = "Basic $encodedCreds"
            'Content-Type' = 'application/json;charset=utf-8'
            Accept         = 'application/json;charset=utf-8'
        }
    } catch {
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
        } elseif ($ErrorObject.Exception.GetType().FullName -eq 'System.Net.WebException') {
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
        } catch {
            $httpErrorObj.FriendlyMessage = $httpErrorObj.ErrorDetails
        }
        Write-Output $httpErrorObj
    }
}
#endregion

try {
    # Initial Assignments
    $outputContext.AccountReference = 'Currently not available'

    # Validate correlation configuration
    if ($actionContext.CorrelationConfiguration.Enabled) {
        $correlationField = $actionContext.CorrelationConfiguration.Personfield
        $correlationValue = $actionContext.CorrelationConfiguration.PersonFieldValue

        if ([string]::IsNullOrEmpty($($correlationField))) {
            throw 'Correlation is enabled but not configured correctly'
        }
        if ([string]::IsNullOrEmpty($($correlationValue))) {
            throw 'Correlation is enabled but [PersonFieldValue] is empty. Please make sure it is correctly mapped'
        }

        # Determine if a user needs to be [created] or [correlated]

        $splatAuthHeaders = @{
            Username = $actionContext.Configuration.UserName
            Password = $actionContext.Configuration.Password
            BaseUrl  = $actionContext.Configuration.BaseUrl
        }

        $AutorizationHeaders = Get-AuthorizationHeaders @splatAuthHeaders

        $splatGetPersons = @{
            Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonalNumber eq '$correlationValue')&`$expand=PersonBaseData(`$select=*)"
            Method  = 'GET'
            Headers = $AutorizationHeaders
        }
        $correlatedAccount = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]

    }

    if ($null -ne $correlatedAccount) {
        $action = 'CorrelateAccount'
    } else {
        $action = 'CreateAccount'
    }

    # Process
    switch ($action) {
        'CreateAccount' {
            $splatCreateParams = @{
                Uri    = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons/Create"
                Method = 'POST'
                Headers = $AutorizationHeaders
                Body   = $actionContext.Data | ConvertTo-Json
            }

            # Make sure to test with special characters and if needed; add utf8 encoding.
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information 'Creating and correlating DormakabaExos account'

                $createdAccount = Invoke-RestMethod @splatCreateParams -Verbose:$false
                $outputContext.Data = $createdAccount.Value
                $outputContext.AccountReference = $createdAccount.Value.PersonId

                # The API does not supports creating disabled accounts

                $splatRestMethodDisable = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons/$($outputContext.AccountReference)/block"
                    Method  = 'Post'
                    Headers = $AutorizationHeaders
                    body    = @{ Reason = 'Automated HelloID Provisioning' } | ConvertTo-Json
                }
                try {
                    $null = Invoke-RestMethod @splatRestMethodDisable -Verbose:$false
                } catch {
                    if ($_.ErrorDetails.message -notmatch 'Person can not be blocked as it has already been blocked') {
                        throw $_
                    }
                }
                break


            } else {
                Write-Information '[DryRun] Create and correlate DormakabaExos account, will be executed during enforcement'
            }
            $auditLogMessage = "Create account was successful. AccountReference is: [$($outputContext.AccountReference)]"
            break
        }

        'CorrelateAccount' {
            Write-Information 'Correlating DormakabaExos account'

            $outputContext.Data = $correlatedAccount
            $outputContext.AccountReference = $correlatedAccount.PersonBaseData.PersonId
            $outputContext.AccountCorrelated = $true
            $auditLogMessage = "Correlated account: [$($outputContext.AccountReference)] on field: [$($correlationField)] with value: [$($correlationValue)]"
            break
        }
    }

    $outputContext.success = $true
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Action  = $action
            Message = $auditLogMessage
            IsError = $false
        })
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-DormakabaExosError -ErrorObject $ex
        $auditMessage = "Could not create or correlate DormakabaExos account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not create or correlate DormakabaExos account. Error: $($ex.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
            Message = $auditMessage
            IsError = $true
        })
}