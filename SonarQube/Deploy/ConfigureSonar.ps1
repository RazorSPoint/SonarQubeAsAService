class SonarQubeCommon {
    static [string] $User
    static [string] $Password
    static [string] $BaseUrl
 }

function Start-SonarApi{
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

function SonarApiCall{
    param (      
        [string]
        $ApiUrl,
        [string]
        $Method,
        [Object]
        $Body
    )
    
    $pair = "$([SonarQubeCommon]::User):$([SonarQubeCommon]::Password)"
    $encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
    
    $basicAuthValue = "Basic $encodedCreds"
    $Headers = @{
        Authorization = $basicAuthValue
    }

    $arguemtents = @{

    }

    Invoke-RestMethod -Uri "$([SonarQubeCommon]::BaseUrl)/$ApiUrl" -Method $Method -Headers $Headers -Body $Body

}

function Set-SonarSetting{
    param(        
        [string]
        $Key,
        [string]
        $Value
    )

    SonarApiCall -ApiUrl "api/settings/set" -Method POST -Body @{
        key = $Key
        value = $Value
    }   
}
Start-SonarApi -User 'admin' -Password 'admin' -BaseUrl 'https://wa-sonarqubetest.azurewebsites.net'


# install azure aad plugin
$availablePlugin = SonarApiCall -ApiUrl "api/plugins/available" -Method Get
$aadPlugin = $availablePlugin.plugins | Where-Object { $_.key -eq "authaad" }

SonarApiCall -ApiUrl "api/plugins/install" -Method POST -Body @{
    key = $aadPlugin.key
}

#Restart-AzWebApp -ResourceGroupName "Default-Web-WestUS" -Name "ContosoSite"
#SonarApiCall -ApiUrl "api/system/restart"  -Method POST

$status = $null
while ($status -ne "pong") {
    $status = SonarApiCall -ApiUrl "api/system/status" -Method GET
    Start-Sleep -Seconds 10
}

#only allow logged in users to see something
Set-SonarSetting -Key "sonar.forceAuthentication" -Value "true"

#set settings for aad plugin
Set-SonarSetting -Key "sonar.auth.aad.tenantId" -Value $AadTenantId
Set-SonarSetting -Key "sonar.auth.aad.clientId.secured" -Value $AadClientId
Set-SonarSetting -Key "sonar.auth.aad.clientSecret.secured" -Value $AadClientSecret
Set-SonarSetting -Key "sonar.auth.aad.enableGroupsSync" -Value "true"
Set-SonarSetting -Key "sonar.auth.aad.loginStrategy" -Value "Same as Azure AD login"
Set-SonarSetting -Key "sonar.auth.aad.enabled" -Value "true"


#$definitions = SonarApiCall -ApiUrl "api/settings/list_definitions" -Method GET

