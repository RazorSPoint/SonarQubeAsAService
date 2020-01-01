$env:SqlServerName = ""
$env:SqlDatabase = ""
$env:SqlDatabaseAdmin = "sebastian"
$env:SqlDatabaseAdminPassword = "Ss//06.1982!"
$env:SonarQubeEdition = "Community"
$env:SonarQubeVersion = "Latest"
$InstallationDirectory = "C:\temp\sonar"

#Get-SonarQube -DestinationPath $InstallationDirectory -Edition $env:SonarQubeEdition -Version $env:SonarQubeVersion


<# Update-SonarConfig  -ConfigFilePath "C:\temp\sonar" `
                    -SqlServerName "sqlsrv-sonarhosting" `
                    -SqlDatabase "sqldb-sonarhosting"`
                    -SqlDatabaseAdmin "sonaradmin"`
                    -SqlDatabaseAdminPassword "sonar2019!"
#>
 & '.\Deploy\ConfigureSonar.ps1' `
    -WebAppName "wa-sonarhosting3jfg98klhepo" `
    -AdminUser "admin" -AdminPassword "admin" `
    -AadTenantId "hhhj" -AadClientId "fff" -AadClientSecret "ddd" 


 #& '.\Deploy\RunPowerShellKudu.ps1' -WebsiteName "wa-SonarHosting" -ResourceGroupName "Rp-SonarQubeAsAService" 