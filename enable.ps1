#####################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Enable
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
                Message = "Enable DormakabaExos account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        Write-Verbose "Enabling DormakabaExos account with accountReference: [$aRef]"
        $splatAuthHeaders = @{
            Username = $config.UserName
            Password = $config.Password
            BaseUrl  = $config.BaseUrl
        }
        $headers = Get-AuthorizationHeaders @splatAuthHeaders

        $splatRestMethod = @{
            Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($aRef)/unblock"
            Method  = 'Post'
            Headers = $headers
            body    = @{ Reason = 'Automated HelloId Provisioing' } | ConvertTo-Json
        }
        try {
            $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
        } catch {
            if ($_.ErrorDetails.message -notmatch 'Person can not be unblocked as it has already been unblocked') {
                throw $_
            }
        }
        $success = $true
        $auditLogs.Add([PSCustomObject]@{
                Message = 'Enable account was successful'
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
