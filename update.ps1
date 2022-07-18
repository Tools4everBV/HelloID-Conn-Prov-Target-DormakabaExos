#####################################################
# HelloID-Conn-Prov-Target-DormakabaExos-Update
#
# Version: 1.0.0
#####################################################
# Initialize default values
$config = $configuration | ConvertFrom-Json
$p = $person | ConvertFrom-Json
$pp = $previousPerson | ConvertFrom-Json
$aRef = $AccountReference | ConvertFrom-Json
$success = $false
$auditLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

# Account mapping
$account = [PSCustomObject]@{
    PersonBaseData = [PSCustomObject]@{
        PersonalNumber = $p.ExternalId
        FirstName      = $p.Name.GivenName
        LastName       = "$($p.Name.FamilyNamePrefix) $($p.Name.FamilyName)".trim(' ')
        EMail          = $p.Accounts.MicrosoftActiveDirectory.mail
    }
}

$previousAccount = [PSCustomObject]@{
    PersonBaseData = [PSCustomObject]@{
        PersonalNumber = $pp.ExternalId
        FirstName      = $pp.Name.GivenName
        LastName       = "$($pp.Name.FamilyNamePrefix) $($pp.Name.FamilyName)".trim(' ')
        EMail          = $pp.Accounts.MicrosoftActiveDirectory.mail
    }
}

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
#endregion

try {
    # Verify if the account must be updated
    $splatCompareProperties = @{
        ReferenceObject  = @($previousAccount.PersonBaseData.PSObject.Properties)
        DifferenceObject = @($account.PersonBaseData.PSObject.Properties)
    }
    $propertiesChanged = (Compare-Object @splatCompareProperties -PassThru).Where({ $_.SideIndicator -eq '=>' })
    if ($propertiesChanged) {
        $action = 'Update'
    } else {
        $action = 'NoChanges'
    }

    # Add an auditMessage showing what will happen during enforcement
    if ($dryRun -eq $true) {
        $auditLogs.Add([PSCustomObject]@{
                Message = "Update DormakabaExos account for: [$($p.DisplayName)] will be executed during enforcement"
            })
    }

    if (-not($dryRun -eq $true)) {
        switch ($action) {
            'Update' {
                Write-Verbose "Updating DormakabaExos account with accountReference: [$aRef]"
                $splatAuthHeaders = @{
                    Username = $config.UserName
                    Password = $config.Password
                    BaseUrl  = $config.BaseUrl
                }
                $headers = Get-AuthorizationHeaders @splatAuthHeaders

                $body = @{
                    PersonBaseData = @{}
                }
                foreach ($property in $propertiesChanged) {
                    $body.PersonBaseData["$($property.name)"] = $property.value
                }
                $splatRestMethod = @{
                    Uri     = "$($Config.BaseUrl)/ExosApi/api/v1.0/persons/$($aRef)/Update"
                    Method  = 'Post'
                    Headers = $headers
                    body    = ($body | ConvertTo-Json -Depth 10)
                }
                $null = Invoke-RestMethod @splatRestMethod -Verbose:$false
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update account was successful'
                        IsError = $false
                    })
                break
            }

            'NoChanges' {
                Write-Verbose "No changes to DormakabaExos account with accountReference: [$aRef]"
                $auditLogs.Add([PSCustomObject]@{
                        Message = 'Update skipped. No change is required to the DormakabaExos account.'
                        IsError = $false
                    })
                break
            }
        }
        $success = $true
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
        Account   = $account
        Auditlogs = $auditLogs
    }
    Write-Output $result | ConvertTo-Json -Depth 10
}
