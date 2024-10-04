##################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Disable
# PowerShell V2
##################################################

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
    # Verify if [aRef] has a value
    if ([string]::IsNullOrEmpty($($actionContext.References.Account))) {
        throw 'The account reference could not be found'
    }

    Write-Information 'Verifying if a DormakabaExos account exists'

    $splatAuthHeaders = @{
        Username = $actionContext.Configuration.UserName
        Password = $actionContext.Configuration.Password
        BaseUrl  = $actionContext.Configuration.BaseUrl
    }

    $Autorizationheaders = Get-AuthorizationHeaders @splatAuthHeaders

    $splatGetPersons = @{
        Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonId eq '$($actionContext.References.Account)')"
        Method  = 'GET'
        Headers = $Autorizationheaders
    }
    $correlatedAccount = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]

    if ($null -ne $correlatedAccount) {
        $action = 'DisableAccount'
    } else {
        $action = 'NotFound'
    }

    # Process
    switch ($action) {
        'DisableAccount' {
            if (-not($actionContext.DryRun -eq $true)) {
                Write-Information "Disabling DormakabaExos account with accountReference: [$($actionContext.References.Account)]"

                $splatRestMethod = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons/$($actionContext.References.Account)/block"
                    Method  = 'Post'
                    Headers = $Autorizationheaders
                    body    = @{ Reason = 'Automated HelloId Provisioing' } | ConvertTo-Json
                }
                try {
                    $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
                } catch {
                    if ($_.ErrorDetails.message -notmatch 'Person can not be blocked as it has already been blocked') {
                        throw $_
                    }
                }

                Write-Information 'Check the badges assigned to the account (if any), and unassign these'
                $splatGetPersons = @{
                    Uri     = "$($actionContext.Configuration.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonId eq '$($actionContext.References.Account)')&`$expand=Badge(`$select=badgename)"
                    Method  = 'GET'
                    Headers = $headers
                }
                $responseUser = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]

                if ($responseUser.Badge.badgeName.count -eq 0) {
                    Write-information "No Badges were assigned to [$($Aref)]"
                } else {
                    foreach ($badge in $responseUser.Badge) {
                        Write-Information "Unassigning Badge [$($badge.BadgeName)]"

                        $splatRestMethod = @{
                            Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($actionContext.References.Account)/unassignBadge"
                            Method  = 'Post'
                            Headers = $headers
                            body    = @{ BadgeName = $badge.BadgeName } | ConvertTo-Json
                        }
                        $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
                        $outputContext.AuditLogs.Add([PSCustomObject]@{
                                Message = "Unassign Badge [$($badge.BadgeName)] was successful"
                                IsError = $false
                            })
                    }
                }

            } else {
                Write-Information "[DryRun] Disable DormakabaExos account with accountReference: [$($actionContext.References.Account)], will be executed during enforcement"
            }

            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = 'Disable account was successful'
                    IsError = $false
                })
            break
        }

        'NotFound' {
            Write-Information "DormakabaExos account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
            $outputContext.Success = $true
            $outputContext.AuditLogs.Add([PSCustomObject]@{
                    Message = "DormakabaExos account: [$($actionContext.References.Account)] could not be found, possibly indicating that it could be deleted"
                    IsError = $false
                })
            break
        }
    }
} catch {
    $outputContext.success = $false
    $ex = $PSItem
    if ($($ex.Exception.GetType().FullName -eq 'Microsoft.PowerShell.Commands.HttpResponseException') -or
        $($ex.Exception.GetType().FullName -eq 'System.Net.WebException')) {
        $errorObj = Resolve-DormakabaExosError -ErrorObject $ex
        $auditMessage = "Could not disable DormakabaExos account. Error: $($errorObj.FriendlyMessage)"
        Write-Warning "Error at Line '$($errorObj.ScriptLineNumber)': $($errorObj.Line). Error: $($errorObj.ErrorDetails)"
    } else {
        $auditMessage = "Could not disable DormakabaExos account. Error: $($_.Exception.Message)"
        Write-Warning "Error at Line '$($ex.InvocationInfo.ScriptLineNumber)': $($ex.InvocationInfo.Line). Error: $($ex.Exception.Message)"
    }
    $outputContext.AuditLogs.Add([PSCustomObject]@{
        Message = $auditMessage
        IsError = $true
    })
}