param(
    [string]
    $SqlServerName,
    [string]
    $SqlDatabase,
    [string]
    $SqlDatabaseAdmin,
    [string]
    $SqlDatabaseAdminPassword
)

Write-Output 'Setting Security to TLS 1.2'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Write-Output 'Prevent the progress meter from trying to access the console'
$global:progressPreference = 'SilentlyContinue'

Write-Output 'Getting a list of downloads'
$downloadSource = 'https://binaries.sonarsource.com/CommercialDistribution/sonarqube-enterprise/'
$allDownloads = Invoke-WebRequest -Uri $downloadSource -UseBasicParsing
$zipFiles = $allDownloads[0].Links | Where-Object { $_.href.EndsWith('.zip') -and !($_.href.contains('alpha') -or $_.href.contains('RC')) }

# We sort by a custom expression so that we sort based on a version and not as a string. This results in the proper order given values such as 7.9.zip and 7.9.1.zip.
#   In the expression we use RegEx to find the "Version.zip" string, then split and grab the first to get just the "Version" and finally cast that to a version object
$sortedZipFiles = $zipFiles | Sort-Object -Property @{ Expression = { [Version]([RegEx]::Match($_.href, '\d+.\d+.?(\d+)?.zip').Value -Split ".zip")[0] } }
$latestFile = $sortedZipFiles[-1]
$downloadUri = $downloadSource + $latestFile.href

Write-Output "Downloading '$downloadUri'"
$outputFile = "..\wwwroot\$($latestFile.href)"
Invoke-WebRequest -Uri $downloadUri -OutFile $outputFile -UseBasicParsing
Write-Output "Done downloading file $outputFile"

Write-Output 'Extracting zip'
Expand-Archive -Path $outputFile -DestinationPath ..\wwwroot
Write-Output 'Extraction complete'

Write-Output 'Searching for sonar.properties files to overwrite'
$propFiles = Get-ChildItem 'sonar.properties' -Recurse
if(!$propFiles) {
    Write-Output "Could not find sonar.properties"
    exit
}
Write-Output "Files found at: `n $($propFile.FullName)"
Write-Output "Moving to sonar.properties file"

$sonarPropertySource = $propFiles[1].FullName
$sonarPropertyTarget = $propFiles[0].FullName

$connectionString = "jdbc:sqlserver://$SqlServerName.database.windows.net:1433;database=$SqlDatabase;encrypt=true;trustServerCertificate=false;hostNameInCertificate=*.database.windows.net;loginTimeout=30;"
((Get-Content -path $sonarPropertySource -Raw) `
    -replace '#SqlAdmin#',$SqlDatabaseAdmin `
    -replace '#SqlAdminPassword#', $SqlDatabaseAdminPassword`
    -replace '#SqlConnectionString#', $connectionString
) | Set-Content -Path $sonarPropertySource
 
#Move-Item -Path $sonarPropertySource -Destination $sonarPropertyTarget -Force