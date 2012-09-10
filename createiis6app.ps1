$frameworkPath = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Client").InstallPath 
set-alias regIIS $frameworkPath\aspnet_regiis.exe

function TestInclude ([string]$name) {
	(get-host).ui.rawui.foregroundcolor= "Magenta"
	$name
	(get-host).ui.rawui.foregroundcolor= "Yellow"
}
function CheckIfAppPoolExists ([string]$name)
{
	$tempPool  = gwmi -namespace "root\MicrosoftIISv2" -class "IISApplicationPoolSetting" -filter "Name like '%$name%'"
	$tempPool -ne $NULL
}

function CheckIfWebSiteExists ([string]$name)
{
	$tempWebsite  = gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '%$name%'"
	$tempWebsite -ne $NULL
}

function CheckIfWebApplicationExists ([string]$webSite, [string]$appName) 
{
	$tempWebsite  = (gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '%$webSite%'")
	$tempApp = (gwmi -namespace "root\MicrosoftIISv2" -class "IISWebDirectory" | where {$_.name -like "$tempWebSite/*$appName" })
	if ($tempApp -ne $NULL) 
	{
    $tempApp.AppGetStatus().returnvalue -ne 2
	} 
	else 
	{ $False }
}

function CheckIfVirtualDirectoryExists ([string]$webSite, [string]$virtualDir)
{
	$True
}

function CreateAppPool ([string]$name) #, [string]$user, [string]$password)
{
	# check if pool exists and delete it - for testing purposes
	"    Creating ISS app pool for " + $name
	$tempPool  = gwmi -namespace "root\MicrosoftIISv2" -class "IISApplicationPoolSetting" -filter "Name like '%$name%'"
	if (($tempPool -eq $NULL)) {

		# create Application Pool
		$appPoolSettings = [wmiclass] "root\MicrosoftIISv2:IISApplicationPoolSetting"
		$newPool = $appPoolSettings.CreateInstance()

		$newPool.Name = "W3SVC/AppPools/" + $name

		$newPool.PeriodicRestartTime = 1740
		$newPool.IdleTimeout = 20
		$newPool.MaxProcesses = 1
		$newPool.AppPoolIdentityType = 3

		$newPool.Put()
	}
}

function CreateWebSite ([string]$name, [string]$localPath, [string] $appPoolName, [string] $applicationName, [string] $hostName, [string] $logLocation)
{
	# check if web site exists and delete it - for testing purposes
	"    Creating IIS website for " + $name
	$tempWebsite  = gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '%$name%'"
	if (($tempWebsite -eq $NULL)) {
	
		$iisWebService  = gwmi -namespace "root\MicrosoftIISv2" -class "IIsWebService"

		$bindingClass = [wmiclass]'root\MicrosoftIISv2:ServerBinding'
		$bindings = $bindingClass.CreateInstance()
		$bindings.Port = "80"
		$bindings.Hostname = $hostname

		EnsurePath $localPath
		$NewSite = $iisWebService.CreateNewSite($name, $bindings, $localPath)

		$webServerSettings  = gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '%$name%'"
		
		# Add wildcard map
		$iis = [ADSI]"IIS://localhost/W3SVC"
		$webServer = $iis.psbase.children | where { $_.keyType -eq "IIsWebServer" -AND $_.ServerComment -eq $name }
		$webserver.AspEnableParentPaths = $True
		$webserver.LogFileDirectory = $logLocation
		$webServer.Properties["AccessFlags"].Value = 513
		$webServer.Properties["AuthFlags"].Value = 1
		$webServer.DefaultDoc = "index.asp," + $webServer.DefaultDoc
		$webServer.AppPoolID = $appPoolName
		$webserver.SetInfo()

		$webVirtualDir = $webServer.children | where { $_.keyType -eq "IIsWebVirtualDir" }
		
		# Set Application name
		$webVirtualDir.AppFriendlyName = $applicationName

		# Save changes
		$webServer.CommitChanges()
		$webVirtualDir.CommitChanges()

		# Switch the Website to .NET 4.0
		$webServerSettings.Name
		regiis -s $webServerSettings.Name

		# Start the newly created web site
		if (!($webServer -eq $NULL)) {$webServer.start()}
	}
}

function CreateWebApplication([string]$webSite, [string]$appName, [string] $appPool, [string]$InstallDir) 
{
	EnsurePath $localPath
	
	$webServerSettings  = gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '%$webSite%'"
    
    $dirSettings = [wmiclass] "root\MicrosoftIISv2:IIsWebDirectory"
    $newDir = $dirSettings.CreateInstance()
    $newDir.Name = ($webServerSettings.Name + '/ROOT/' + $appName)
    $newDir.Description = $appPool
    $newDir.Put()
    
    $newDir.AppCreate3(2, $appPool, $True)
}

function CreateVirtualDirectory([string]$webSite, [string]$virtualDir, [string]$physicalPath)
{
	"Virtual directory won't be created"
}


function AddSslCertificate ([string] $websiteName, [string] $certificateCommonName)
{
	# This method requires for you to have selfssl on your machine
	$selfSslPath = "\program files\iis resources\selfssl"

	$certificateCommonName = "/N:cn=" + $certificateCommonName

	$certificateValidityDays = "/V:3650"
	$websitePort = "/P:443"
	$addToTrusted = "/T"
	$quietMode = "/Q"


	$webServerSetting = gwmi -namespace "root\MicrosoftIISv2" -class "IISWebServerSetting" -filter "ServerComment like '$websiteName'"
	$websiteId ="/S:" + $webServerSetting.name.substring($webServerSetting.name.lastindexof('/')+1)

	cd -path $selfSslPath
	.\selfssl.exe $addToTrusted $certificateCommonName $certificateValidityDays $websitePort $websiteId $quietMode
}
