<#
 .SYNOPSIS
 Starts the PowerShell script on the web app via Kudu.
 
 .DESCRIPTION
 Starts the PowerShell script on the web app via Kudu. Kudu is being used to trigger the deployment script to install SonarQube on the web app.
 
 .PARAMETER WebsiteName
 Name of the web app to run the deployment script

 .PARAMETER SqlServerName
 Base name of the SQL server (not the URL!).

 .PARAMETER SqlDatabase
 Name of the SQL database.

 .PARAMETER SqlDatabaseAdmin
 SQL login name of the admin.

 .PARAMETER SqlDatabaseAdminPassword
 SQL login password of the admin.

#>
[CmdletBinding()]
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
$SqlDatabaseAdminPassword)

$creds = Invoke-AzResourceAction `
-ResourceType "Microsoft.Web/sites/config" `
-ResourceName "$WebsiteName/publishingcredentials" `
-Action list -ApiVersion 2015-08-01 -Force

$username = $creds.Properties.PublishingUserName
$password = $creds.Properties.PublishingPassword
$base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

$apiBaseUrl = "https://$WebsiteName.scm.azurewebsites.net/api"

$scriptCallString = "& `"`$pwd\Deploy-SonarQubeAzureAppService.ps1`" -SqlServerName `"$SqlServerName`" -SqlDatabase `"$SqlDatabase`" -SqlDatabaseAdmin `"$SqlDatabaseAdmin`" -SqlDatabaseAdminPassword `"$SqlDatabaseAdminPassword`""
$commandBody = @{
    command = "powershell -NoProfile -NoLogo -ExecutionPolicy Unrestricted -Command `"$scriptCallString 2>&1 | echo`""
    dir = "site\\wwwroot"
}

$result = Invoke-RestMethod -Uri "$apiBaseUrl/command" -Headers @{Authorization=("Basic {0}" -f $base64AuthInfo)} -Method POST -ContentType "application/json" -Body (ConvertTo-Json $commandBody)

if($result.Output){
    $result.Output
}

if($result.Error){
    $result.Error
    throw "An error occured during kudu command execution"
}

