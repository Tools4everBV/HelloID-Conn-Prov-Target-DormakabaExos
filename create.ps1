#####################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Create
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    PersonBaseData = @{
        PersonalNumber = $p.ExternalId
        FirstName      = $p.Name.GivenName
        LastName       = "$($p.Name.FamilyNamePrefix) $($p.Name.FamilyName)".trim(' ')
        EMail          = $p.Accounts.MicrosoftActiveDirectory.mail
    }
}

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

# Set to true if accounts in the target system must be updated
$updatePerson = $false

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
#endregion functions

# Begin
try {
    $splatAuthHeaders = @{
        Username = $config.UserName
        Password = $config.Password
        BaseUrl  = $config.BaseUrl
    }
    $headers = Get-AuthorizationHeaders @splatAuthHeaders

    Write-Verbose "Get ExosUser [$($account.PersonBaseData.PersonalNumber)]"-Verbose
    $splatGetPersons = @{
        Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonalNumber eq '$($account.PersonBaseData.PersonalNumber)')&`$expand=PersonBaseData(`$select=*)"
        Method  = 'GET'
        Headers = $headers
    }
    $responseUser = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]

    if (-not($responseUser)) {
        $action = 'Create-Correlate'
    } elseif ($updatePerson -eq $true) {
        $action = 'Update-Correlate'
    } else {
        $action = 'Correlate'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action DormakabaExos account for: [$($p.DisplayName)], will be executed during enforcement"
            })
    }

    # Process
    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Create-Correlate' {
                Write-Verbose 'Creating and correlating DormakabaExos account'
                $splatRestMethodCreate = @{
                    Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/Create"
                    Method  = 'Post'
                    Headers = $headers
                    body    = ($account | ConvertTo-Json -Depth 10)
                }
                $responseUser = Invoke-RestMethod @splatRestMethodCreate -Verbose:$false
                $accountReference = $responseUser.Value.PersonId


                # The API does not supports creating disabled accounts
                $splatRestMethodDisable = @{
                    Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($accountReference)/block"
                    Method  = 'Post'
                    Headers = $headers
                    body    = @{ Reason = 'Automated HelloId Provisioing' } | ConvertTo-Json
                }
                try {
                    $null = Invoke-RestMethod @splatRestMethodDisable -Verbose:$false
                } catch {
                    if ($_.ErrorDetails.message -notmatch 'Person can not be blocked as it has already been blocked') {
                        throw $_
                    }
                }
                break
            }

            'Update-Correlate' {
                Write-Verbose 'Updating and correlating DormakabaExos account'
                $splatRestMethod = @{
                    Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($responseUser.PersonBaseData.PersonId)/Update"
                    Method  = 'Post'
                    Headers = $headers
                    body    = ($account | ConvertTo-Json -Depth 10)
                }
                $responseUser = Invoke-RestMethod @splatRestMethod -Verbose:$false
                $accountReference = $responseUser.Value.PersonId
                break
            }

            'Correlate' {
                Write-Verbose 'Correlating DormakabaExos account'
                $accountReference = $responseUser.PersonBaseData.PersonId
                break
            }
        }

        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = "$action account was successful. AccountReference is: [$accountReference]"
                IsError = $false
            })
    }
} catch {
    $errorMessage = "Could not $action DormakabaExos account. Error: $($_.Exception.Message)  $($_.ErrorDetails.message)"
    Write-Verbose $errorMessage -Verbose
    $auditLogs.Add([PSCustomObject]@{
            Message = $errorMessage
            IsError = $true
        })
} finally {
    if ($null -ne $headers) {
        Write-Verbose 'logout'
        $splatLogOut = @{
            Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/logins/logoutMyself"
            Method  = 'POST'
            Headers = $headers
        }
        try {
            $null = Invoke-RestMethod @splatLogOut -Verbose:$false
        } catch {
            Write-Verbose "Warning LogoutMyself Failed, $($_.Exception.Message)  $($_.ErrorDetails.message)".trim(' ') -Verbose
        }
    }

    $result = [PSCustomObject]@{
        Success          = $success
        AccountReference = $accountReference
        Auditlogs        = $auditLogs
        Account          = $account
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
