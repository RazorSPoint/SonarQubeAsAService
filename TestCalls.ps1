& '.Deploy\RunPowerShellKudu.ps1' `
    -WebsiteName "mykuduest" `
    -SqlServerName "sqlserv-sonarqubetest" `
    -SqlDatabase "sqldb-sonarqubetest"`
    -SqlDatabaseAdmin "sonaradmin"`
    -SqlDatabaseAdminPassword "sonar2019!"`
    -ResourceGroupName "RG_SonarQubeTest02_DEV"