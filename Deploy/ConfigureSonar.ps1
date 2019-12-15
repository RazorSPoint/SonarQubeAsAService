[CmdletBinding(DefaultParameterSetName = 'IntegratedLogin')]
param (
    [string]
    [Parameter(ParameterSetName = 'AzureADLogin')]
    [Parameter(ParameterSetName = 'IntegratedLogin')]
    $WebAppName = "wa-sonarhosting",
    [string]
    [Parameter(ParameterSetName = 'IntegratedLogin')]
    [Parameter(ParameterSetName = 'AzureADLogin')]
    $AdminUser = 'admin',
    [string]
    [Parameter(ParameterSetName = 'IntegratedLogin')]
    [Parameter(ParameterSetName = 'AzureADLogin')]
    $AdminPassword = 'admin',
    [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
    [string]
    $AadTenantId,
    [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
    [string]
    $AadClientId,
    [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
    [string]
    $AadClientSecret
)


class SonarQubeCommon {
    static [string] $User
    static [string] $Password
    static [string] $BaseUrl
}

function Start-SonarApi {
    param(
        [string]
        $User,
        [string]
        $Password,
        [string]
        $BaseUrl
    )

    [SonarQubeCommon]::User = $User
    [SonarQubeCommon]::Password = $Password
    [SonarQubeCommon]::BaseUrl = $BaseUrl
}

function Invoke-SonarApiCall {
    [CmdletBinding()]
    param (      
        [string]
        $ApiUrl,
        [string]
        $Method,
        [Object]
        $Body,
        [ValidateRange(0, [Int32]::MaxValue)]
        [Int]
        $TimeoutSec = 30
    )
    
    $pair = "$([SonarQubeCommon]::User):$([SonarQubeCommon]::Password)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    
    $basicAuthValue = "Basic $encodedCreds"
    $Headers = @{
        Authorization = $basicAuthValue
    }

    $arguments = @{
        Uri           = "$([SonarQubeCommon]::BaseUrl)/$ApiUrl"
        Method        = $Method
        Headers       = $Headers
        Body          = $Body
        ErrorVariable = "ResponseError"
    }

    if ($TimeoutSec) {
        $arguments.Add('TimeoutSec', $TimeoutSec)
    }

    $result = Invoke-RestMethod  @arguments -ErrorAction SilentlyContinue

    if ($ResponseError) {
        return $ResponseError
    }else{
        return $result
    }
}

function Set-SonarSetting {
    [CmdletBinding()]
    param(        
        [string]
        $Key,
        [string]
        $Value
    )

    Write-Output "Updating setting $Key with value $Value."
    $null = Invoke-SonarApiCall -ApiUrl "api/settings/set" -Method POST -Body @{
        key   = $Key
        value = $Value
    }   
}

function Invoke-RestartSonarQube {
    [CmdletBinding()]
    param (
        [string]
        $WebAppName = "wa-sonarhosting",
        [ValidateRange(0, [Int32]::MaxValue)]
        [Int]
        $MaximumRetryCount = 0,
        [ValidateRange(1, [Int32]::MaxValue)]
        [Int]
        $RetryIntervalSec = 5
    )

    $status = $null
    $retryCount = 1

    Write-Output "Restarting Sonarqube Server"
    $webApp = Get-AzWebApp -Name $WebAppName
    $null = Restart-AzWebApp -ResourceGroupName $webApp.ResourceGroup -Name $webApp.Name
    Start-Sleep -Seconds 30
    #Invoke-SonarApiCall -ApiUrl "api/system/restart" -Method POST

    while ($retryCount -le $MaximumRetryCount) {        
        Write-Output "Trying to ping server. Try number $retryCount."
        $response = Invoke-SonarApiCall -ApiUrl "api/system/status" -Method GET -TimeoutSec 150

        if ($null -ne $response -and $response.status -eq "UP") {            
            Write-Output "Server is up and running."
            break
        }
        else {
            Write-Output "Server not yet up, retry in $RetryIntervalSec."
            Start-Sleep -Seconds $RetryIntervalSec
        } 
        $retryCount = $retryCount + 1       
    }
}

function Install-SonarQubePlugin {
    [CmdletBinding()]
    param (
        [string]
        $Name
    )

    $installedPlugins = Invoke-SonarApiCall -ApiUrl "api/plugins/installed" -Method Get
    $isInstalled = $null -ne ($installedPlugins.plugins | Where-Object { $_.key -eq $Name })

    if ($isInstalled) {

        Write-Warning "Plugin $Name is already installed"
        return $false

    }
    else {

        $availablePlugin = Invoke-SonarApiCall -ApiUrl "api/plugins/available" -Method Get
        $aadPlugin = $availablePlugin.plugins | Where-Object { $_.key -eq $Name }
        Write-Output "Installing Plugin $Name"
        Invoke-SonarApiCall -ApiUrl "api/plugins/install" -Method POST -Body @{
            key = $aadPlugin.key
        }        
    }

    Write-Output "Plugin $Name installed successfully, server needs to be restarted"
    return $true
}

function Initialize-SonarQubeConfiguration {
    [CmdletBinding(DefaultParameterSetName = 'IntegratedLogin')]
    param (
        [string]
        [Parameter(ParameterSetName = 'AzureADLogin')]
        [Parameter(ParameterSetName = 'IntegratedLogin')]
        $WebAppName = "wa-sonarhosting",
        [string]
        [Parameter(ParameterSetName = 'IntegratedLogin')]
        [Parameter(ParameterSetName = 'AzureADLogin')]
        $AdminUser = 'admin',
        [string]
        [Parameter(ParameterSetName = 'IntegratedLogin')]
        [Parameter(ParameterSetName = 'AzureADLogin')]
        $AdminPassword = 'admin',
        [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
        [string]
        $AadTenantId,
        [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
        [string]
        $AadClientId,
        [Parameter(Mandatory = $true, ParameterSetName = 'AzureADLogin')]
        [string]
        $AadClientSecret
    )

    $SonarBaseUrl = "https://$WebAppName.azurewebsites.net"

    Start-SonarApi -User $AdminUser -Password $AdminPassword -BaseUrl $SonarBaseUrl


    #only allow logged in users to see something
    Set-SonarSetting -Key "sonar.forceAuthentication" -Value "true"

    #set settings for aad plugin
    if ($PsCmdlet.ParameterSetName -eq "AzureADLogin") {

        # install azure aad plugin
        $needsRestart = Install-SonarQubePlugin -Name "authaad"
        $needsRestart = $true
        if ($needsRestart ) {
            Invoke-RestartSonarQube -MaximumRetryCount 5 -RetryIntervalSec 45 -WebAppName $WebAppName
        }

        Set-SonarSetting -Key "sonar.auth.aad.tenantId" -Value $AadTenantId
        Set-SonarSetting -Key "sonar.auth.aad.clientId.secured" -Value $AadClientId
        Set-SonarSetting -Key "sonar.auth.aad.clientSecret.secured" -Value $AadClientSecret
        Set-SonarSetting -Key "sonar.auth.aad.enableGroupsSync" -Value "true"
        Set-SonarSetting -Key "sonar.auth.aad.loginStrategy" -Value "Same as Azure AD login"
        #Set-SonarSetting -Key "sonar.auth.aad.enabled" -Value "true"
    }
}

Initialize-SonarQubeConfiguration `
    -WebAppName $WebAppName `
    -AdminUser $AdminUser -AdminPassword $AdminPassword `
    -AadTenantId $AadTenantId -AadClientId $AadClientId -AadClientSecret $AadClientSecret
