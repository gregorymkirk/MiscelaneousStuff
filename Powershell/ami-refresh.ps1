# This script will given the cluster name and ppipeline arn get the latest image from the pipleine and
# create a new Lauch template version using the updated AMI for each Managed workgroup
# Then it will update the Managed workgroups to use the new AMI.
# Need to add logging of which AMI/date of AMI is being used for the replacement.

Param (
    [Alias("P")][string]$pipelineARN,
    [Alias("C")][Parameter(Mandatory)][string]$cluster,
    [Alias("A")][Parameter(Mandatory)][string]$AWSprofile,
    [Alias("R")][Parameter(Mandatory)][string]$AWSregion,
    [Alias("U")][string]$userdata,
    [string]$AMI
)


Function Main {
    #Install the required modules, fail and exit with error if they do not install
    $ModuleList = "aws.tools.eks","aws.tools.common","AWS.Tools.EC2","AWS.Tools.IdentityManagement","aws.tools.imagebuilder"
    $Install = InstallDeps $ModuleList
    if (!$Install) {
        Write-Host "Failed to install all required Modules"
        Exit 1
    }
    #Set up our credentials and test to see if they work.  Exit with error if they don't
    Initialize-AWSDefaults -ProfileName $AWSprofile -Region $AWSregion
    Try{
    $alias = Get-IamAccountAlias
       }
    Catch {
        Write-Host "ERROR: Unable to determine working account, exiting!"
        Exit 1
    }
    Write-Host "INFO: Operating on $alias"

    # Unless an AMI id is pecified We want to automatically pull the most recent AMI from the pipeline.
    # get the list of AMIs from our pipleine, sort in descending order 
    # We need to refine this to limit results to good amis.
    if (!([string]::IsNullOrEmpty($AMI))) { 
        $amiinfo = Get-Ec2Image -IMageId $AMI
    }
    else {
        try {
            Write-Host "getting most recent AMI from pipeline: $pipelinearn"    
            $List=Get-EC2IBImagePipelineImageList -ImagePipelineArn $pipelinearn
        }
        Catch {
            Write-Host "ERROR: Unable to retrive list of AMIs from pipeline, exiting!"
            Exit 1
        }
        $List= $List| ?{ $_.state.status -eq 'AVAILABLE'} |Sort-object -Property DateCreated -Descending

        #The first AMI will be the most recent, get the imageID from that one.
        $AMIid = $List[0].OutputResources.amis.image
        $amiinfo = Get-Ec2Image -IMageId $AMIid
    }
    Write-Host "INFO: Updating nodegroups to use AMI $($amiinfo.Name) ($AMIId)"
    if (!([string]::IsNullOrEmpty($userdata))){
        Write-Host "INFO:  Userdata script will be updated using contents of $userdata"

    }
    # Handle the updating of the user data
    if (!([string]::IsNullOrEmpty($userdata))) {
        $userdatatxt=Get-Content $userdata -Raw
        $userdata64= [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($userdatatxt))
        Write-Host "Using file $userdata to replace userdata scripts attached to launch templates"
    }
    else{ Write-Host "No file specified for user data  scripts, Userdata scripts will not be updated"}
 
    $NodeGroups=get-EKSNodeGroupList -ClusterName $cluster
    $lts=@()
    foreach($Nodegroup in $NodeGroups) {
        #we should be able to do this in Powershell, but a bug means the launch template data is returned as a null.
        # so we used the cli and converted the json output
        $ng= $($(aws eks describe-nodegroup  --cluster-name $cluster --nodegroup-name $Nodegroup)|convertfrom-json).nodegroup
        $LTid= $ng.launchTemplate.id
        $LTlatest = $(Get-EC2Template -LaunchTemplateId $LTid).LatestVersionNumber
        $lts=  $Lts + $Ltid 
    }
    $lts=$lts|sort-object|Get-Unique -AsString
    
    $ltvers=@{}
    ForEach ($ltid in $Lts) {
        $LTlatest = $(Get-EC2Template -LaunchTemplateId $LTid).LatestVersionNumber
        $ltvers.add( $ltid, $LTLatest)

    }
     #Update the Launch Template
    Foreach ($LTid in $lts) {
        $LTver=$Ltvers.$LTid
        $LTtemplate=$(Get-EC2TemplateVersion -LaunchTemplateId $LTid -Version $LTver).Launchtemplatedata
        $LTTemplate.ImageId=$AMIid  
        if (!([string]::IsNullOrEmpty($userdata64))){$LTTemplate.UserData = $userdata64 }
        $LTData=New-Object -TypeName Amazon.EC2.Model.RequestLaunchTemplateData
        [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($LTTemplate.UserData))
        New-EC2LaunchTemplateVersion -LaunchTemplateData $LTData -SourceTemplateData $LTtemplate -LaunchTemplateId $LTid 
        $LTvers.$LTid=$(Get-EC2Template -LaunchTemplateId $LTid).LatestVersionNumber
        Write-host "INFO: New Launch Template $LTid version $($LTvers.$LTid) created"
    }


    foreach($Nodegroup in $NodeGroups) {
        #we should be able to do this in Powershell, but a bug means the launch template data is returned as a null.
        # so we used the cli and converted the json output
        $ng= $($(aws eks describe-nodegroup  --cluster-name $cluster --nodegroup-name $Nodegroup)|convertfrom-json).nodegroup
        $LTid= $ng.launchTemplate.id
        $Ltver=$Ltvers.$Ltid
        eksctl upgrade nodegroup --name=$NodeGroup --cluster=$cluster --launch-template-version=$Ltver --timeout 3h --force-upgrade
	# Wait 10 minutes between nodegroups to ensure that long startup time pods have sufficient time to come up
        start-sleep -s 600
    }  
}

Function InstallDeps{
    # Accepts a list of modules, checks to see if they are installed, if not installs them 
    # Then imports the modules.  Returns false if any module fails to install or load.
    Param([Object]$ModuleList)
    $AWSToolsModules = $ModuleList| where-object{$_ -like "aws.tools.*"}
    $OtherModules =  $ModuleList| where-object{$_ -notlike "aws.tools.*"}
    set-PSrepository -Name PSGallery -InstallationPolicy Trusted

    ForEach ($Module in $OtherModules){

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
    }
    if ($AWSToolsModules.count -ne 0) {
        #Make sure we have the AWS.Tools.Installer
        if (!(Get-InstalledModule -Name "AWS.Tools.Installer" )){ 
            write-host "AWS.Tools.Installer not found"
            Try {install-module -Name "AWS.Tools.Installer" -Force -AcceptLicense -AllowClobber -Repository PSGallery}
            catch  {
                "Unable to install required AWS.Tools.Installer Module from PSGallery" |Tee-Object -Path $errorlog -Append 
                return $False
                } 
            }
            Try {Import-Module "AWS.Tools.Installer" }
            catch {
                "Unable to import required AWS.Tools.Installer Module" |Tee-Object -Path $errorlog -Append 
                return $False
            }
        ForEach ($Module in $AWSToolsModules){
            if (!(Get-InstalledModule -Name $Module )){ 
            Try {Install-AWSToolsModule -Name $Module -Force -AcceptLicense -AllowClobber -Repository PSGallery}
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
        }
    }
    Return $True
}


    
Main
