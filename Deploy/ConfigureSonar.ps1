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

function Connect-SQServer {
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

    Write-Verbose "Calling: $($arguments.Method) - $($arguments.Uri)"
    try {
        $response = Invoke-WebRequest @arguments -ErrorAction SilentlyContinue
    }
    catch{
       
    }
    
    if ($null -ne $response -and $response.StatusCode -like "2*") {
        $response.Content | ConvertFrom-Json
    }
    else {
        Write-Host $ResponseError.Message -ErrorAction Stop
        return "Error" 
    }

}

function Set-SQSetting {
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

function Install-SQPlugin {
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

function Get-SQInfo {
    <#
    .SYNOPSIS
        Gets a number of states from the SonarQube server.
    .DESCRIPTION
        Gets a number of states from the SonarQube server, can be used in conjunction with other functions in this module such as Restart-SonarQubeServer.
        You can be creative, try diferent combinations. You can also see the examples.
    .EXAMPLE
        $status = Get-SonarQubeInfo -serverStatus
        if ($status -eq "UP") {Write-Output "Your sonarqube server is up, good job!"}
    #>
    param(
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


    $result = Invoke-SonarApiCall -ApiUrl "api/$apiUrl" -Method Get

    if($result -eq 'Error'){
        $result
    }else{
        $result.$option
    }    
}

function Wait-SQStart {
    <#
    .SYNOPSIS
        Waits for SonarQube server to become available from different states.
    .DESCRIPTION
        Waits for SonarQube server to become available from different states. 
        It is useful when you just restarted the server or after a database schema was initiated and you need to do something else after for example.
    .EXAMPLE
        Restart-SQServer
        Wait-SQStart
    #>
    
    if (!(Get-Command Get-SQInfo)) {
        Write-Output "Did not found prerequisite cmdlet, stoping execution"
        exit
    }

    $started = $false
    Do {
        
        $status = Get-SQInfo -serverStatus 

        switch ($status) {
            'UP' { Write-Output "SonarQube status: $status SonarQube Online!" ; $started = $true }
            'DOWN' { Write-Output "SonarQube is down for some reason, please review the logs for details"; exit }
            { $_ -in 'STARTING', 'RESTARTING', 'DB_MIGRATION_RUNNING' } { Write-Output "SonarQube status: $status, waiting for SonarQube service to start.." ; Start-Sleep -Seconds 5 }
            { $_ -in 'DB_MIGRATION_NEEDED' } { Write-Output "Your SonarQube needs a dbschema migration, stopping"; exit }
            { $_ -in 'Error' } { Write-Output "SonarQube status: $status, waiting for SonarQube service to start.." ; Start-Sleep -Seconds 10 }
        }

    }
    Until ($started)
}

function Restart-SQServer {
    <#
    .SYNOPSIS
        Restarts the SonarQube server.
    .DESCRIPTION
        Restarts the SonarQube server. You might need to do that after you install, uninstall, updated plugins for example.
    .EXAMPLE        
        Restart-SonarQubeServer
        Wait-SonarQubeStart
    #>
    [CmdletBinding()]
    param (
        [string]
        $WebAppName = "wa-sonarhosting"
    )

    Write-Information "Restarting Sonarqube Server"
    if($WebAppName){
        $webApp = Get-AzWebApp -Name $WebAppName       
        $null = Restart-AzWebApp -ResourceGroupName $webApp.ResourceGroup -Name $webApp.Name
        Start-Sleep -Seconds 30 
    }else{
        $null = Invoke-SonarApiCall -ApiUrl "api/system/restart" -Method Post
    }

    Write-Output "Restarting SonarQube server, please wait.."
}


function Initialize-SQConfiguration {
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

    Connect-SQServer -User $AdminUser -Password $AdminPassword -BaseUrl $SonarBaseUrl
    Wait-SQStart -Uri $SonarBaseUrl

    #only allow logged in users to see something
    Set-SQSetting -Key "sonar.forceAuthentication" -Value "true"

    #set settings for aad plugin
    if ($PsCmdlet.ParameterSetName -eq "AzureADLogin") {

        # install azure aad plugin
        $needsRestart = Install-SQPlugin -Name "authaad"
        $needsRestart = $true

        if ($needsRestart ) {
            Restart-SQServer -WebAppName $WebAppName
            Wait-SQStart -Uri $SonarBaseUrl
        }

        Set-SQSetting -Key "sonar.auth.aad.tenantId" -Value $AadTenantId
        Set-SQSetting -Key "sonar.auth.aad.clientId.secured" -Value $AadClientId
        Set-SQSetting -Key "sonar.auth.aad.clientSecret.secured" -Value $AadClientSecret
        Set-SQSetting -Key "sonar.auth.aad.enableGroupsSync" -Value "true"
        Set-SQSetting -Key "sonar.auth.aad.loginStrategy" -Value "Same as Azure AD login"
        #Set-SQSetting -Key "sonar.auth.aad.enabled" -Value "true"
    }
}

$InformationPreference = "Continue"

Initialize-SQConfiguration `
    -WebAppName $WebAppName `
    -AdminUser $AdminUser -AdminPassword $AdminPassword `
    -AadTenantId $AadTenantId -AadClientId $AadClientId -AadClientSecret $AadClientSecret
