#RemotePC import Script RemotePCLoad.ps1
#This script can be used to import computers and user assignments from a CSV file
#and to apply them to a private desktop catalog in Citrix Virtual Apps and Desktops

#Version 1.0 3-18-2020
#Version 1.1 3-19-2020

function Get-ScriptDirectory
{
  $Invocation = (Get-Variable MyInvocation -Scope 1).Value
  Split-Path $Invocation.MyCommand.Path
}

Function LogLine($strLine)
{
	Write-Host $strLine
	$StrTime = Get-Date -Format "MM-dd-yyyy-HH-mm-ss-tt"
	"$StrTime - $strLine " | Out-file -FilePath $LogFile -Encoding ASCII -Append
}


#Script Setup
#===================================================================
$adminAddress = "XD1"
$domain = "citrix"
#note $adminaddress is ignored when using the cloud sdk
$CatalogNamePrefix = "MachineCatalog_"
$csvName = "input.txt"
$AddComputers = $true
$AddUsers = $true
$AllowMultipleUsers = $true
$CheckResultsComputers = $true
$CheckResultsUsers = $true
#===================================================================

$ScriptSource = Get-ScriptDirectory
$ErrorActionPreference = 'stop'
#Create a log folder and file
$LogFolderName = Get-Date -Format "yyyyMMddHHmmss"
$LogTopFolder = "$ScriptSource\Logs"

If (!(Test-Path "$LogTopFolder"))
{
	mkdir "$LogTopFolder" >$null
}

$LogFolder = "$LogTopFolder\$LogFolderName"
mkdir "$LogFolder" >$null
$LogFile = "$LogFolder\RemotePC_Import_log.txt"

Logline "Running RemotePC Import Script"

$CsvFile = "$ScriptSource\$csvName"
if (Test-Path $CsvFile)
{
	Logline "Found CSV file will import"
	#Get Map csv file
	$MapUsers = Import-Csv -Path $CsvFile -Encoding ASCII
}


#Lets see if the Citrix Broker Admin snapin is loaded and if not load it.
$Snapins =  Get-PSSnapin

foreach ($Snapin in $Snapins) 
{
	If ($Snapin.Name -eq "Citrix.Broker.Admin.V2")
	{
		Logline "Snapin Citrix.Broker.Admin.V2 already loaded!"
		$SnapinLoaded = $True
		break
	}

}

if (!$SnapinLoaded)
{
	Logline "Loading Snapin Citrix.Broker.Admin.V2"
	asnp Citrix*
}

#Now lets make sure it loaded
$SnapinLoaded = $false
$Snapins2 =  Get-PSSnapin

foreach ($Snapin in $Snapins2) 
{
	If ($Snapin.Name -eq "Citrix.Broker.Admin.V2")
	{
		$SnapinLoaded = $True
		break
	}

}
if (!$SnapinLoaded)
{
		Logline "****Snapin [Citrix.Broker.Admin.V2] could not loaded - Exiting Script"
		Throw "Snapin Could not be loaded.  Exiting Script"
		break
}

Try {
    
    $CatalogName = $CatalogNamePrefix + (Get-Date -Format "yyyyMMdd")
    #Create New Catalog if needed
    $RemotePCCatalog = Get-BrokerCatalog -Name $CatalogName -ErrorAction:SilentlyContinue
    if($RemotePCCatalog -eq $null)
    {
        Logline "Creating Machine Catalog [$CatalogName]"
	    $RemotePCCatalog = New-BrokerCatalog -AdminAddress $adminAddress -AllocationType "Permanent" -IsRemotePC $False -MachinesArePhysical $True -MinimumFunctionalLevel "L7_9" -Name $CatalogName -PersistUserChanges "OnLocal" -ProvisioningType "Manual" -SessionSupport "SingleSession"
    }
    else
    {
        Logline "Machine Catalog [$CatalogName] already exists."
    }
}
Catch {
	Logline "Catalog could not be obtained.  Exiting script"
	Throw "Catalog Could not be loaded.  Exiting Script"
	break
}

if ($AddComputers)
{
	#First Loop through the list and add the computers to the catalog
	Logline "================================================================"
	logline "             Adding Computers to Catalog"
	Logline ""

	foreach ($UserMapping in $MapUsers)
	{

		$Machine = $UserMapping.NomeMacchina.Trim()
        echo $Machine
        $UserName = $UserMapping.Utente.Trim()
        echo $UserName

        if ($Machine.length -eq 0)
		{
			Logline "**** Machine Name for User [$UserName] is null skipping to next machine"
			continue
		}

		Try {
			Logline "Adding Machine [$machine] to Catalog [$CatalogName]"
			New-BrokerMachine -MachineName $Machine -CatalogUid $RemotePCCatalog.Uid -AdminAddress $adminAddress 
        }
		Catch {
			$ErrorValue = $error[0] 
            if ($ErrorValue -like '*Machine is already allocated')
            {
                Logline "Machine [$machine] has already been added to Catalog [$CatalogName]."
            }
            else
            {
                Logline "=========================================================="
                Logline "**** Adding Machine [$machine] to Catalog [$CatalogName] FAILED"
				Logline $Error[0]
				Logline "=========================================================="
            }
		}
	}

	#Start-Sleep 60
}

if ($AddUsers)
{
	#Now Loop through the list again and assign the users to the computers
	Logline "================================================================"
	logline "             Assigning Users to Computers"
	Logline ""

	foreach ($UserMapping in $MapUsers)
	{
		$Machine = $domain + "\" + $UserMapping.NomeMacchina.Trim()
		$UserName = $UserMapping.Utente.Trim()
		if ($Machine.length -eq 0)
		{
			Logline "+++++ Desktop Name is blank for user [$UserName]. User will not be added"
			continue
		}
        if ($UserName.length -eq 0)
		{
			Logline "+++++ No User Defined for Desktop [$Machine]. User will not be added"
			continue
		}

		$GetDesktop = Get-BrokerMachine $Machine -AdminAddress $adminAddress -ErrorAction:SilentlyContinue
		if ($GetDesktop -isnot [Citrix.Broker.Admin.SDK.Machine])
		{
			Logline "**** Desktop [$machine] not found in catalog [$CatalogName]"
			Logline "**** Skipping to next user"
			continue
		}
		
		$GetAssignedUser = Get-BrokerUser -AdminAddress $adminAddress -MachineUid $GetDesktop.Uid
		if ($GetAssignedUser.Count -gt 1){$AssignedUserTest = $GetAssignedUser[0]}else{$AssignedUserTest = $GetAssignedUser}
		if ($AssignedUserTest -isnot [Citrix.Broker.Admin.SDK.User])
		{
			#We will assign the user
			Logline "Mapping user [$UserName] to Desktop [$Machine]"
			try {
				Add-BrokerUser -AdminAddress $adminAddress -Machine $Machine -Name $UserName
			}
			Catch {
				Logline "=========================================================="
				Logline "Error Adding User [$UserName] to Desktop [$Machine]"
				Logline $Error[0]
				Logline "=========================================================="
			}
			
		}
		elseif ($AllowMultipleUsers)
		{
			[System.Collections.ArrayList]$ArrAssUsers = @()
			foreach ($assUser in $GetAssignedUser)
			{
				$AssignedUser = $assUser.Name
				$ArrAssUsers.Add($AssignedUser)
			}
			
			if ( $ArrAssUsers -notcontains $UserName)
			{
				Logline "Adding additional User [$UserName] to Desktop [$Machine]"
				try {
					Add-BrokerUser -AdminAddress $adminAddress -PrivateDesktop $Machine -Name $UserName
				}
				Catch {
					Logline "=========================================================="
					Logline "Error Adding User [$UserName] to Desktop [$Machine]"
					Logline $Error[0]
					Logline "=========================================================="
				}
			}
		}
		else
		{
			$AssignedUser = $GetAssignedUser.Name
			Logline "+++ User already mapped to Desktop [$Machine] Mapped User [$UserName] Assigned User [$AssignedUser]"
		}
	 
	}
	Start-Sleep 60
} # End AddUsers
