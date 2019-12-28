<#
 .SYNOPSIS
 Is downloading sonarqube, unpacking it and then configuring the properties file with the given database information
 
 .DESCRIPTION
 Is downloading sonarqube, unpacking it and then configuring the properties file with the given database information

.PARAMETER InstallationDirectory
 Directory to where the SonarQube is supposed to be installed on the server.

#>
[CmdletBinding()]
param(
    [string]
    $InstallationDirectory = "..\wwwroot"
)

function Get-SQDownloadUri {
    [CmdletBinding()]
    param(  
        [Parameter(Mandatory = $false)]      
        [string]
        $Edition = 'Community',
        [Parameter(Mandatory = $true)]
        [string]
        $Version
    )

    Write-Information "Getting a list of downloads for $Edition edition."
    $downloadFolder = 'Distribution/sonarqube' # Community Edition
    $fileNamePart = 'sonarqube' # Community Edition
    switch ($Edition) {
        'Developer' { 
            $downloadFolder = 'CommercialDistribution/sonarqube-developer' 
            $fileNamePart = 'sonarqube-developer' 
        }
        'Enterprise' { 
            $downloadFolder = 'CommercialDistribution/sonarqube-enterprise'
            $fileNamePart = 'sonarqube-enterprise'
        }
        'Data Center' { 
            $downloadFolder = 'CommercialDistribution/sonarqube-datacenter'
            $fileNamePart = 'sonarqube-datacenter'
        }
    }

    $downloadSource = "https://binaries.sonarsource.com/$downloadFolder"
    $downloadUri = ''
    $fileName = ''
    if (!$Version -or ($Version -ieq 'Latest')) {
        Write-Information "Getting the latest version of $Edition edition."
        $allDownloads = Invoke-WebRequest -Uri $downloadSource -UseBasicParsing
        $zipFiles = $allDownloads[0].Links | Where-Object { $_.href.EndsWith('.zip') -and !($_.href.contains('alpha') -or $_.href.contains('RC')) }

        # We sort by a custom expression so that we sort based on a version and not as a string. This results in the proper order given values such as 7.9.zip and 7.9.1.zip.
        # In the expression we use RegEx to find the "Version.zip" string, then split and grab the first to get just the "Version" and finally cast that to a version object
        $sortedZipFiles = $zipFiles | Sort-Object -Property @{ Expression = { [Version]([RegEx]::Match($_.href, '\d+.\d+.?(\d+)?.zip').Value -Split ".zip")[0] } }
        $latestFile = $sortedZipFiles[-1]
        $downloadUri = "$downloadSource/$($latestFile.href)"
        $fileName = $latestFile.href
    }
    else {
        Write-Information "Using version $Version of $Edition edition."
        $fileName = "$fileNamePart-$Version.zip"
        $downloadUri = "$downloadSource/$fileName"
    }

    if (!$downloadUri -or !$fileName) {
        throw 'Could not get download uri or filename.'
    }

    return $downloadUri
}

function Get-SonarQube { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]      
        [string]
        $DestinationPath,
        [Parameter(Mandatory = $true)]      
        [string]
        $Edition,
        [Parameter(Mandatory = $true)]
        [string]
        $Version
    ) 
    <#
    .SYNOPSIS
    Is downloading sonarqube from the official source, unpacking it and deleting the downloaded package file
    
    .DESCRIPTION
    Is downloading sonarqube from the official source, unpacking it and deleting the downloaded package file
    
    .PARAMETER DestinationPath
    Directory to where the SonarQube is supposed to be installed on the server.

    #>
    
    Write-Output 'Getting a the download URI'
    $downloadUri = Get-SQDownloadUri -Edition $Edition -Version $Version

    Write-Output "Downloading '$downloadUri'"
    $fileName = $downloadUri | Split-Path -Leaf
    $outputFile = "$DestinationPath\$($fileName)"
    Invoke-WebRequest -Uri $downloadUri -OutFile $outputFile -UseBasicParsing
    Write-Output "Done downloading file $outputFile"

    Write-Output 'Extracting zip'
    Expand-Archive -Path $outputFile -DestinationPath $DestinationPath -Force
    Write-Output 'Extraction complete'

    Write-Output "Deleting downloaded file $outputFile"
    Remove-Item -Path $outputFile -Force
    Write-Output "File deleted successfully"
}

function Update-SonarConfig { 
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $ConfigFilePath, 
        [Parameter(Mandatory = $true)]
        [string]
        $SqlServerName,
        [Parameter(Mandatory = $true)]
        [string]
        $SqlDatabase,
        [Parameter(Mandatory = $true)]
        [string]
        $SqlDatabaseAdmin,
        [Parameter(Mandatory = $true)]
        [string]
        $SqlDatabaseAdminPassword
    )
    <#
    .SYNOPSIS
    Is updating the sonarqube porperties file with the given parameters
    
    .DESCRIPTION
    Is updating the sonarqube porperties file with the given parameters
    
    .PARAMETER ConfigFilePath
    Path to the template of sonar.properties file.
     
    .PARAMETER SqlServerName
    Base name of the SQL server (not the URL!).

    .PARAMETER SqlDatabase
    Name of the SQL database.

    .PARAMETER SqlDatabaseAdmin
    SQL login name of the admin.

    .PARAMETER SqlDatabaseAdminPassword
    SQL login password of the admin.

    #>
    
    Write-Output 'Searching for sonar.properties files to overwrite'
    $propFiles = Get-ChildItem  -File "$ConfigFilePath/sonar.properties" -Recurse
    
    if (!$propFiles) {
        Write-Output "Could not find sonar.properties"
        exit
    }

    Write-Output "Files found at: `n $($propFiles.FullName)"
    Write-Output "Moving to sonar.properties file"

    $sonarPropertySource = $propFiles[1].FullName
    $sonarPropertyTarget = $propFiles[0].FullName

    $connectionString = "jdbc:sqlserver://$SqlServerName.database.windows.net:1433;database=$SqlDatabase;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
    ((Get-Content -path $sonarPropertySource -Raw) `
            -replace '#SqlAdmin#', $SqlDatabaseAdmin `
            -replace '#SqlAdminPassword#', $SqlDatabaseAdminPassword`
            -replace '#SqlConnectionString#', $connectionString
    ) | Set-Content -Path $sonarPropertySource
 
    Move-Item -Path $sonarPropertySource -Destination $sonarPropertyTarget -Force
}

Write-Output 'Setting Security to TLS 1.2'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Output 'Prevent the progress meter from trying to access the console'
$global:progressPreference = 'SilentlyContinue'

#All Variables are expected to be present in the environment. 
#In the case of the solution it would be the web app config variables, which are by default adressable through $env:MyVariable

Get-SonarQube -DestinationPath $InstallationDirectory -Edition $env:SonarQubeEdition -Version $env:SonarQubeVersion

Update-SonarConfig -ConfigFilePath $InstallationDirectory `
    -SqlServerName $env:SqlServerName `
    -SqlDatabase $env:SqlDatabase `
    -SqlDatabaseAdmin $env:SqlDatabaseAdmin `
    -SqlDatabaseAdminPassword $env:SqlDatabaseAdminPassword

if ($false -eq (Test-Path -Path logs)) {
    New-Item -Path logs -ItemType Directory
}