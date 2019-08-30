
param(
[string]
$WebsiteName,
[string]
$SqlServerName,
[string]
$SqlDatabase,
[string]
$SqlDatabaseAdmin,
[string]
$SqlDatabaseAdminPassword,
[string]
$ResourceGroupName)

$creds = Invoke-AzResourceAction `
-ResourceGroupName $ResourceGroupName `
-ResourceType "Microsoft.Web/sites/config" `
-ResourceName "$WebsiteName/publishingcredentials" `
-Action list -ApiVersion 2015-08-01 -Force

$username = $creds.Properties.PublishingUserName
$password = $creds.Properties.PublishingPassword
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

$apiBaseUrl = "https://$WebsiteName.scm.azurewebsites.net/api"

$scriptCallString = "$pwd\Deploy-SonarQubeAzureAppService.ps1 -SqlServerName '$SqlServerName' -SqlDatabase '$SqlDatabase' -SqlDatabaseAdmin '$SqlDatabaseAdmin' -SqlDatabaseAdminPassword '$SqlDatabaseAdminPassword'"
$commandBody = @{
    command = "powershell -NoProfile -NoLogo -ExecutionPolicy Unrestricted -Command ""& ""$scriptCallString"" 2>&1 | echo"""
    dir = "site\\wwwroot"
}

Invoke-RestMethod -Uri "$apiBaseUrl/command" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method POST -ContentType "application/json" -Body (ConvertTo-Json $commandBody)