#https://github.com/Razvanxp/SonarQubePS/blob/master/SQFramework.psm1

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

    Write-Information "Calling: $($arguments.Method) - $($arguments.Uri)"
    try {
        $result = Invoke-RestMethod  @arguments -ErrorAction SilentlyContinue
    }
    catch{
        $result = $ResponseError
    }
    
    return $result
}

function Set-SonarSetting {
    [CmdletBinding()]
    param(        
        [string]
        $Key,
        [string]
        $Value
    )

    Write-Information "Updating setting $Key with value $Value."
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

    $response = $null
    $retryCount = 1

    Write-Information "Restarting Sonarqube Server"
    $webApp = Get-AzWebApp -Name $WebAppName
    $null = Restart-AzWebApp -ResourceGroupName $webApp.ResourceGroup -Name $webApp.Name
    Start-Sleep -Seconds 30
    #Invoke-SonarApiCall -ApiUrl "api/system/restart" -Method POST

    while ($retryCount -le $MaximumRetryCount) {        
        Write-Information "Trying to ping server. Try number $retryCount."
        $response = Invoke-SonarApiCall -ApiUrl "api/system/status" -Method GET -TimeoutSec 150

        if ($null -ne $response -and $response.status -eq "UP") {            
            Write-Information "Server is up and running."
            break
        }
        else {
            Write-Information "Server not yet up, retry in $RetryIntervalSec."
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
        Write-Information "Installing Plugin $Name"
        Invoke-SonarApiCall -ApiUrl "api/plugins/install" -Method POST -Body @{
            key = $aadPlugin.key
        }        
    }

    Write-Information "Plugin $Name installed successfully, server needs to be restarted"
    return $true
}


function New-AuthHeader {
    <#
    .SYNOPSIS
        Creates an authentication header based on username/password or access token that can be used with the other functions in this module to create requests
    .DESCRIPTION
        Creates an authentication header based on username/password or access token that can be used with the other functions in this module to create requests
    .EXAMPLE
        Get-SonarQubePlugins -Uri https://mysonar.com -Header (New-AuthHeader -username sonaruser -password mypassword) -Installed
    .EXAMPLE
        $Header = New-AuthHeader -username sonaruser -password mypassword
        Get-SonarQubePlugins -Uri https://mysonar.com -Header $Header -Installed
        Get-SonarQubePlugins -Uri https://mysonar.com -Header $Header -Pending
    .EXAMPLE
        $Header = New-AuthHeader -token <PAT>
        Get-SonarQubePlugins -Uri https://mysonar.com -Header $Header -Installed
    #>
    param(
        [Parameter(ParameterSetName = "credentials", Mandatory = $True)]
        [string]$username,
        [string]$password,
        [Parameter(ParameterSetName = "token", Mandatory = $True)]
        [string]$token
    )

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    switch ($PSBoundParameters.Keys) {
        'username' { $encodedString = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes("$($username):$($password)")) }

        'token' { $encodedString = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$token")) }
    }

    $Header = @{
        Authorization = "Basic $encodedString"
    }
    return $Header
}

function Get-SonarQubeInfo {
    <#
    .SYNOPSIS
        Gets a number of states from the SonarQube server.
    .DESCRIPTION
        Gets a number of states from the SonarQube server, can be used in conjunction with other functions in this module such as Restart-SonarQubeServer.
        You can be creative, try diferent combinations. You can also see the examples.
    .EXAMPLE
        $Header = New-AuthHeader -username sonaruser -password mypassword
        $status = Get-SonarQubeInfo -Uri https://mysonar.com -Header $Header -serverStatus
        if ($status -eq "UP") {Write-Output "Your sonarqube server is up, good job!"}
    #>
    param(
        [Parameter(Mandatory = $true)]
        $Uri,
        [Parameter(Mandatory = $true)]
        $Header,
        [Parameter(ParameterSetName = "serverVersion", Mandatory = $True)]
        [switch]$serverVersion,
        [Parameter(ParameterSetName = "serverStatus", Mandatory = $True)]
        [switch]$serverStatus,
        [Parameter(ParameterSetName = "dbMigrationStatus", Mandatory = $True)]
        [switch]$dbMigrationStatus,
        [Parameter(ParameterSetName = "systemUpgrades", Mandatory = $True)]
        [switch]$systemUpgrades
    )

    switch ($PSBoundParameters.Keys) {
        'serverVersion' { $apiUrl = 'system/status'; $option = "version" }

        'serverStatus' { $apiUrl = 'system/status'; $option = "status" }

        'dbMigrationStatus' { $apiUrl = 'system/db_migration_status'; $option = 'state' }

        'systemUpgrades' { $apiUrl = 'system/upgrades'; $option = 'upgrades' }
    }

    try {
        $response = Invoke-WebRequest -Uri "$Uri/api/$apiUrl" -Method Get -Headers $Header -ErrorVariable ResponseError
    }
    catch {

    }

    if ($response.StatusCode -eq 200) {

        $status = $response.Content | ConvertFrom-Json
        $status.$option
    }
    else {
        Write-Host $ResponseError.Message -ErrorAction Stop
        return "Error" 
    }

}

function Wait-SonarQubeStart {
    <#
    .SYNOPSIS
        Waits for SonarQube server to become available from different states.
    .DESCRIPTION
        Waits for SonarQube server to become available from different states. 
        It is useful when you just restarted the server or after a database schema was initiated and you need to do something else after for example.
    .EXAMPLE
        $Header = New-AuthHeader -username sonaruser -password mypassword
        Restart-SonarQubeServer -Uri https://mysonar.com -Header $Header
        Wait-SonarQubeStart -Uri https://mysonar.com -Header $Header
    #>
    param (
        [ValidateNotNullOrEmpty()]$Uri
      ##  [ValidateNotNullOrEmpty()]$Header
    )
    
    if (!(Get-Command Get-SonarQubeInfo)) {
        Write-Output "Did not found prerequisite cmdlet, stoping execution"
        exit
    }

    $started = $false
    Do {
        
        $status = Get-SonarQubeInfo -Uri $Uri -Header $Header -serverStatus 

        switch ($status) {
            'UP' { Write-Output "SonarQube status: $status SonarQube Online!" ; $started = $true }
            'DOWN' { Write-Output "SonarQube is down for some reason, please review the logs for details"; exit }
            { $_ -in 'STARTING', 'RESTARTING', 'DB_MIGRATION_RUNNING' } { Write-Output "SonarQube status: $status, waiting for SonarQube service to start.." ; Start-Sleep -Seconds 5 }
            { $_ -in 'DB_MIGRATION_NEEDED' } { Write-Output "Your SonarQube needs a dbschema migration, stopping"; exit }
            { $_ -in 'Error' } { Write-Output "SonarQube status: $status, waiting for SonarQube service to start.." ; Start-Sleep -Seconds 5 }
        }

    }
    Until ($started)
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

    $header = New-AuthHeader -username $AdminUser -password $AdminPassword
    Wait-SonarQubeStart -Uri $SonarBaseUrl -Header $header

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

$InformationPreference = "Continue"

Initialize-SonarQubeConfiguration `
    -WebAppName $WebAppName `
    -AdminUser $AdminUser -AdminPassword $AdminPassword `
    -AadTenantId $AadTenantId -AadClientId $AadClientId -AadClientSecret $AadClientSecret
