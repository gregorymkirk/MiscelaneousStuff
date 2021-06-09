Param(
    [Parameter(Mandatory=$True)][string]$CommandId,
    [Parameter(Mandatory=$True)][string]$Profile 
    )




Function Main {
    
    $ModuleList= "AWS.Tools.Common","AWS.Tools.IdentityManagement", "AWS.Tools.SimpleSystemsManagement","AWS.Tools.Ec2"
    InstallDeps $ModuleList
    
    Initialize-AWSDefaults -ProfileName $profile -Region us-gov-west-1

    $account = get-iamaccountalias
    #add a test for valid AWS
    Write-host "Operating on $account"

    $datestamp = get-date -Format "yyMMddHHmm"
    $errorlog = ".\$datestamp-error.log"
    $logfile = ".\$datestamp-log.log"

    $status = (Get-SSMCommand -CommandId $CommandId).Status.Value 
    Write-host "Command $CommandId completed with status: $status"

    If ($status -ne "Success") {
        Write-Host "Patch Process not successful, exited with status $status, Check status of $CommandId)"
         "Patch Process not successful, exited with status $status, Check status of $CommandId)" | Out-file -Append -Filepath $errorlog
    }
    Else {
        $results = Get-SSMCommandInvocation -CommandID $CommandId
        $Errorcount = 0 
        foreach ($Instance in $results) {
            if ($Instance.status.value -ne "Success") {
              "$($Instance.InstanceID) - $($instance.InstanceName) - Patchin Status: $($instance.Status.value)" | Out-file -Append -Filepath $errorlog
               $Errorcount++
               #out to error log file 
            }
            else  {
                "$($Instance.InstanceID) - $($instance.InstanceName) - Patched $($Instance.Status.value)" | Out-file -Append -Filepath $logfile 
                $node = (kubectl get node $Instance.InstanceName --output=json)|out-string|convertFrom-json
                if ($node){
                    $master = [bool]($node.metadata.labels.PSobject.Properties.name -match "node-role.kubernetes.io/master")
                    if (!$master) { 
                        # Drain the node, 
                        kubectl drain $instance.InstanceName  --delete-local-data --ignore-daemonsets --force --grace-period=300 --timeout 600s
                    }
                    # Ec2HardRestart is a function that stops then starts the intance,
                    # working around issues where the instance fails to respond to a reboot request
                    $restart= Ec2HardRestart $Instance.InstanceID
                    if ($restart -eq 1) { 
                        #We shoudl trap this and recover?
                    }
                    if ($restart -eq 2) {
                        # Status Checks failed, try to restart the server again
                        #we need better trapping & handling here though
                         $retry = Ec2HardRestart $Instance.InstanceID
                    }
                    #While loop to confirm that node is ready
                    $count = 0
                    while ( (testkubestatus $Instance.InstanceName) -ne "True"){
                        Start-sleep 15
                        $count++
                        if ($count > 11) { 
                        "TERMINATING SCRIPT EXECUTION - Node  $($instance.InstanceName) / $($Instance.InstanceID) Kubelet Failed to restart."| Out-file -Append -Filepath $errorlog
                        Write-Host "TERMINATING Node  $($instance.InstanceName) / $($Instance.InstanceID) Kubelet Failed to restart."
                        Exit
                        }
                    }
                    if (!$master) { 
                        # Uncordon the node
                        kubectl uncordon  $instance.InstanceName  
                    }

                }      

                else {
                    "Node  $($instance.InstanceName) / $($Instance.InstanceID) not found in this cluster, reboot manually"| Out-file -Append -Filepath $errorlog
                     $Errorcount++
                }
            }
        }
    }

    if ( $Errorcount -gt 0) {Write-Host "$Errorcount Instances did not patch successfully, check $errorlog for details"}

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
Function testkubestatus  {
    Param([string]$NodeName)
     $node =( kubectl get node $NodeName --output=json)|out-string|ConvertFrom-Json
     $status = $node.status.conditions.status[$node.status.conditions.reason.indexof("KubeletReady")]
     return $status
}

Function InstanceOK {
    # Checks the Instance status, Retuns $True if both status checks are OK, false if either is failing
    Param([string]$InstanceID)
    $iStatus = Get-EC2InstanceStatus -InstanceId $InstanceId 
    if ( ( $istatus.Status.Status.value -eq "ok" ) -AND ($iStatus.SystemStatus.Status.value -eq "ok" ) ){ Return $True }
    else {Return $False }
}

function Ec2HardRestart {
    #Stops and starts and EC2 isntance
    # Return Values:
    # 0 = Succcess
    # 1 = Failed to stop Instance
    # 2 = Instance is not passing status checks
    Param([string]$InstanceID)
    Write-host "Stopping $InstanceId"
    Stop-EC2Instance -InstanceId $InstanceId -Force
    start-sleep 45
    #While loop until the instance stops
    $count = 0
    Do {
        Start-sleep 15
        $EC2status= (Get-EC2Instance -InstanceId $InstanceId).instances.state.code
        Write-host "$InstanceId - $EC2status $count"
        if ($count -gt 16) { 
            return 1
        } 
    } While ( $EC2status -ne 80 )
    Write-Host "$InstanceID stopped"

    Start-EC2Instance -InstanceId $InstanceId -Force
    Write-Host "$InstanceID Starting"
    start-sleep 45
    $count = 0
   DO {
        Start-sleep 15
        Write-host "Waiting for $instanceId to become ready $count"
        $OK = InstanceOK $InstanceId 
        $count++
        if ($count -gt 32) { 
            return 2
        }
    }  While ( !( $OK ))
    Return 0
}
 
Main 