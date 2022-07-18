#####################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Disable
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Enable TLS1.2
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

# Set debug logging
switch ($($config.IsDebug)) {
    $true { $VerbosePreference = 'Continue' }
    $false { $VerbosePreference = 'SilentlyContinue' }
}

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

try {
    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Disable DormakabaExos account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Disabling DormakabaExos account with accountReference: [$aRef]"
        $splatAuthHeaders = @{
            Username = $config.UserName
            Password = $config.Password
            BaseUrl  = $config.BaseUrl
        }
        $headers = Get-AuthorizationHeaders @splatAuthHeaders

        $splatRestMethod = @{
            Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($aRef)/block"
            Method  = 'Post'
            Headers = $headers
            body    = @{ Reason = 'Automated HelloId Provisioing' } | ConvertTo-Json
        }
        try {
            $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
        } catch {
            if ($_.ErrorDetails.message -notmatch 'Person can not be blocked as it has already been blocked') {
                throw $_
            }
        }

        Write-Verbose 'Verify if the account has badges assigned.'
        $splatGetPersons = @{
            Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons?`$filter=(PersonBaseData/PersonId eq '$($Aref)')&`$expand=Badge(`$select=badgename)"
            Method  = 'GET'
            Headers = $headers
        }
        $responseUser = (Invoke-RestMethod @splatGetPersons -Verbose:$false).value[0]

        if ($responseUser.Badge.badgeName.count -eq 0) {
            Write-Verbose "No Badges were assigned to [$($Aref)]"
        } else {
            foreach ($badge in $responseUser.Badge) {
                Write-Verbose "Unassign Badge [$($badge.BadgeName)]"

                $splatRestMethod = @{
                    Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($aRef)/unassignBadge"  # Odata Query
                    Method  = 'Post'
                    Headers = $headers
                    body    = @{ BadgeName = $badge.BadgeName } | ConvertTo-Json
                }
                $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
                $auditLogs.Add([PSCustomObject]@{
                        Message = "Unassign Badge [$($badge.BadgeName)] was successful"
                        IsError = $false
                    })
            }
        }
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = 'Disable account was successful'
                IsError = $false
            })
    }
} catch {
    $errorMessage = "Could not update DormakabaExos account. Error: $($_.Exception.Message)  $($_.ErrorDetails.message)"
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
        Success   = $success
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
