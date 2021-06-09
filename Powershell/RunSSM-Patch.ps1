
Param(
    [Parameter(Mandatory=$True)][string]$AWSProfile,
    [Parameter(Mandatory=$True)][string]$Tag
)

# Test Credentials

if ($Profile -ne $null){
    write-host "Using AWS Profile $AWSProfile"
    Initialize-AWSDefaults -ProfileName $AWSprofile -Region us-gov-west-1
}


Function Main {

    $ModuleList= "AWS.Tools.Common","AWS.Tools.IdentityManagement", "AWS.Tools.SimpleSystemsManagement"
    $Install = InstallDeps $ModuleList
    if (!$Install) {
        Write-Host "Failed to install all required Modules"
        Exit 1
    }
   
    Try{
    $alias = Get-IamAccountAlias
    }
    Catch {
        Write-Host "Unable to determine working account, exiting!"
        Exit 1
    }
    $PatchScript = @( "yum-config-manager --disable kubernetes;yum -y update --skip-broken;[ $? = 0 ] && yum -y update --skip-broken")
    $SSMRunCommandID = RunScript -Script $PatchScript -Tag $Tag
    $CheckScript = @( "yum check-update")
    $SSMCheckCommandID = RunScript -Script $CheckScript -Tag $Tag

    OutputReview -CommandId $SSMCheckCommandID
}

Function OutputReview {
    Param(
        [Parameter(Mandatory=$True)]$CommandId
    )
    $J = Get-ssmCommandInvocation -CommandId $CommandID

    forEACH ($I in $J) {
        $detail = Get-SSMCommandInvocationDetail -CommandID $I.commandID -InstanceId $I.InstanceId
        "$($detail.InstanceID)"|Tee-Object -Filepath .\outfile.log -Append
        "$($detail.StandardOutputContent)"|Tee-Object -Filepath .\outfile.log -Append
    }
}
Function RunScript {
    Param(
        [Parameter(Mandatory=$True)]$Script,
        [Parameter(Mandatory=$True)][string]$Tag
    )
   
    $params=  @{'commands'= $script}
  
   $targets = @{Key = "tag:PatchGroup";Values = @($Tag)}

    $SSMCommand = Send-SSMCommand `
    -CloudWatchOutputConfig_CloudWatchOutputEnabled $True `
     -DocumentName "AWS-RunShellScript" `
     -MaxConcurrency "100" `
     -MaxError "100" `
     -Parameter $params `
     -Target $Targets `
     -TimeoutSeconds 600 

    Do {
        Write-Host "Waiting for command $($SSMCommand.CommandId) to complete ($script)"
        Start-Sleep 15
        $CmdStatus = (Get-SSMCommand -CommandId $SSMCommand.CommandId)
    } While ( ($CmdStatus.Status.Value -eq "Pending") -or  ($CmdStatus.Status.Value -eq "InProgress")) 
    
    Return $SSMCommand.CommandId
}

Function InstallDeps{
    # Accepts a list of modules, checks to see if they are installed, if not installs them 
    # Then imports the modules.  Returns false if any module fails to install or load.
    Param([Object]$ModuleList)
    ForEach ($Module in $ModuleList){
        set-PSrepository -Name PSGallery -InstallationPolicy Trusted
        if (!(Get-InstalledModule -Name $Module )){ 
           Try {install-module -Name $Module -Force -AcceptLicense -AllowClobber -Repository PSGallery}
           catch  {
            "Unable to install required Module $Module from PSGallery" |Tee-Object -Path $errorlog -Append 
            return $False
            } 
        }
        Try {Import-Module $Module }
        catch {
            "Unable to import required Module $Module" |Tee-Object -Path $errorlog -Append 
            return $False
        }
        Return $True
    }
}

Main
