#ECR-ScanFindingsReport-Running v0.1
Param(
    [Parameter(Mandatory=$true)][Alias("P")][string]$awsProfile,
    [Parameter(Mandatory=$true)][Alias("R")][string]$awsRegion
    )
Function Main {
    $ModuleList= "ImportExcel","AWS.Tools.Common","AWS.Tools.ECR", "AWS.Tools.Eks","AWS.Tools.IdentityManagement", "Aws.Tools.Ecs"
    InstallDeps $ModuleList
	Initialize-AWSDefaults -ProfileName $awsProfile -Region $awsRegion

    $DateCode=get-date -Format "yyyy-MM-dd"
    $filename= "ECR-Scan-Findings-$DateCode.xlsx"
    Write-Host "Writing report to $filename"

    #Initialize the prefecth cache for CVEs
    $global:PrefetchCache=[ordered]@{}

    # this architecture bit is really rough, and hasn;t been tested for arm stuff, but is here in case we start running this on an arm64
    $rawarch=arch
    switch ( $rawarch ) 
    {
        x86_64  { $arch="amd64"}
        #Need to validate the acutal value returned by and ARM processer instance.
        arm     { $arch="arm64" }
        default { $arch="amd64" }
    }

    #Report on the EKS CLusters
    # if we end up with more than 100 clusters we will need to deal with output pagination. That's a long way away/
    $EKSClusters=get-eksclusterlist
    foreach ($Cluster in $EKSClusters){
        $Images= GetEKSClusterImages -cluster $Cluster -arch $arch
        if ($Images.count -eq 0){
            $data= "No Images found, possible error accessing Cluster"
            }
        else {
            $report= ReportFindings -images $images
            $data = ConvertFrom-csv -Delimiter ';' -Inputobject $report
            }
        #We need to add the report as a tab in the excel sheet, not its own file
        Export-Excel -Inputobject $data -WorksheetName $Cluster -Path "./$filename"
    }

    #Report on the ECS CLusters
    $ECSClusters=get-ecsclusterlist
    foreach ($Cluster in $ECSClusters){
        $Images= GetECSClusterImages -cluster $Cluster -arch $arch
        if ($Images.count -eq 0){
            $data= "No Images found,Cluster may not have any running tasks"
        }
        else {
            $report= ReportFindings -images $images
            $data = ConvertFrom-csv -Delimiter ';' -Inputobject $report
        }
        #Shortening the Clustername 
        $worksheet=($Cluster.split('/')[1])
        if ($worksheet.length() -gt 30 ) { $worksheet=$worksheet.Substring(0,30)}
        Export-Excel -Inputobject $data -WorksheetName $worksheet -Path "./$filename"
    }
}

Function GetEKSClusterImages ([string]$cluster, [string]$arch){
    #Returns a list of conatiner images used in a specified EKS cluster
    $ThisCluster = Get-EKSCluster -Name $Cluster
    # Clean up the kubconfig files 
    if (Test-Path -Path "$home/.kube/config" ) { Remove-Item -Path "$home/.kube/*" -recurse -Force}
    aws eks update-kubeconfig --name $Cluster --region $awsRegion

    #Get the right version of kubectl for this cluster  
    if ( -not(Test-Path -Path "$PWD/kubetemp") ) {new-Item -Path "$PWD/kubetemp" -ItemType "directory"}
    invoke-webrequest -URI "https://dl.k8s.io/release/v$($ThisCluster.Version).0/bin/linux/$arch/kubectl" -OutFile "$PWD/kubetemp/kubectl"
    chmod +x "$PWD/kubetemp/kubectl"

    # Retrive a list of running pods, and the the image information from them
    $Pods=./kubetemp/kubectl get pods -A -o json|convertfrom-json -asHashTable
    $Images = @()
    foreach($item in $pods.items){
        foreach ($container in $item.status.containerStatuses) {
            $Images += ($container.image)
        }
    }
    $Images=($Images|Sort-object -Unique)
    return $Images
}

Function GetECSClusterImages([string]$cluster){
    $Images=@()
    $tasks=get-ECSTaskList -Cluster $cluster
    $TaskDefs=@()
    foreach($task in $tasks){
            $TaskDef=((get-ecsTaskDetail -Cluster $cluster -Task $task).tasks.TaskDefinitionArn)
            $TaskDefs += $Taskdef
    }
    #$TaskDefs=$TaskDefs|Sort-Object -Unique
    $TaskDefs = $TaskDefs | Sort-Object -Unique
    foreach($taskdef in $TaskDefs) {
        $Specs=(Get-ECSTaskDefinitionDetail -TaskDefinition $TaskDef).TaskDefinition.ContainerDefinitions.image
        foreach($Spec in $Specs){
            $Image=$Spec.split("@")[0]
            $Images += $Image
        }
    }
    Return $Images
}

Function ReportFindings ($images) {
    $report = "Repository; Tag; Vulnerability; Upstream Priority; CVSS_Version; CVSS_Score; CVSS_Severity; Vector_String; package_name; package_version; Description`n"
    foreach($image in $images) {
        $tag=$image.split(":")[1]
        $reponame=($image.split(":")[0]).split("/", 2)[1]
        $findings = Get-ECRImageScanFinding -RepositoryName $reponame -ImageId_ImageTag $tag
        foreach ($finding in $findings) {
            foreach ($vulnerability in $finding.ImageScanFindings.Findings ){
                $VULNName = $Vulnerability.Name
                $Description= $Vulnerability.Description.replace("`r", "").replace("`n", " ")
                if ($($Vulnerability.Name.StartsWith("CVE-"))){
                    $Scores= PrefetchLookup -CVE $VULNName
                    $vuln = "$reponame;$tag; $($Vulnerability.Name); $($Vulnerability.Severity); $($Scores.cvssVersion) ; $($Scores.cvssScore); $($Scores.cvssSeverity); $($Scores.cvssVectorString);$($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_name')]); $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_version')]);$Description`n"
                }
                else {
                    $vuln = "$reponame;$tag; $($Vulnerability.Name); $($Vulnerability.Severity); ""N/A"" ; ""N/A""; ""N/A""; ""N/A""; $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_name')]); $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_version')]);$Description+`n"
                }
                if ($vuln -ne $oldvuln) {$report += $vuln}
                $oldvuln=$vuln
            }
        }
    }
    return $report
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
            write-host "Unable to install required Module $Module from PSGallery"  
            return $False
            } 
        }
        Try {Import-Module $Module }
        catch {
            write-host "Unable to import required Module $Module" 
            return $False
        }
    }
    if ($AWSToolsModules.count -ne 0) {
        #Make sure we have the AWS.Tools.Installer
        if (!(Get-InstalledModule -Name "AWS.Tools.Installer" )){ 
            write-host "AWS.Tools.Installer not found"
            Try {install-module -Name "AWS.Tools.Installer" -Force -AcceptLicense -AllowClobber -Repository PSGallery}
            catch  {
                write-host "Unable to install required AWS.Tools.Installer Module from PSGallery" 
                return $False
                } 
            }
            Try {Import-Module "AWS.Tools.Installer" }
            catch {
                write-host "Unable to import required AWS.Tools.Installer Module" 
                return $False
            }
        ForEach ($Module in $AWSToolsModules){
            if (!(Get-InstalledModule -Name $Module )){ 
            Try {Install-AWSToolsModule -Name $Module -Force -AcceptLicense -AllowClobber -Repository PSGallery}
            catch  {
                write-host "Unable to install required Module $Module from PSGallery" 
                return $False
                } 
            }
            Try {Import-Module $Module }
            catch {
                write-host "Unable to import required Module $Module"  
                return $False
            }
        }
    }
    Return $True
}

Function cvsslookup {
    # We will return a hastable with CVSS 2 & 3 scores and severity ratings if it success
    # Otherwise we are going to return False.
    # Older vulnerabilities may not have a CVSS3 score or severity.   Not sure yet hwo this will handle that.
    param(
        [Parameter(Mandatory=$true)][string]$CVE
    )
	$CVE=$CVE.toupper()
    $baseurl= 'https://services.nvd.nist.gov/rest/json/cves/2.0?cveId='
    start-sleep -Seconds 10 #wait 10 seconds before calling the URL.  Once we have the API key working we won't need to wait as long.
    $req=$(invoke-webrequest "$baseurl$CVE")
    #only proceed if we got a good response
 
    If ($req.StatusCode -eq 200) {
        $result = $req.content|out-string| Convertfrom-Json -AsHashtable 
        $metrics= $result.vulnerabilities.cve.metrics.cvssMetricV31
        $Index= $result.vulnerabilities.cve.metrics.cvssMetricV31.type.indexof("Primary")
        
        $cvssVersion=$metrics[$index].cvssData.version
        $cvssScore = $metrics[$index].cvssData.baseScore
			if ($null -eq $cvssv3score ) {$cvssv3score = "N/A"}
        $cvssseverity = $metrics[$index].cvssData.baseSeverity
			if ($null -eq$cvssv3severity ) {$cvssv3severity = "N/A"}
        $cvssVectorString = $result.result.CVE_Items.impact.baseMetricV2.impactScore
			if ($null -eq$cvssV2score ) {$cvssV2score = "N/A"}
        $cvssV2severity = $result.result.CVE_Items.impact.baseMetricV2.severity
          if ($null -eq$cvssV2severity ) {$cvssV2severity = "N/A"}

        $scores = @{ 
            cvssVersion=$cvssVersion
            cvssScore = $cvssScore ; 
            cvssSeverity = $cvssSeverity; 
            cvssVectorString = $cvssVectorString
        }
        return $scores

    }
Else{
        #Return an error since API call failed
        #Maybe return the Web status code?
        return $False
    }
}
function PrefetchLookup {
    # $PrefectchCache should be defined as a global bar outside the scope of this function.
    #We use a global variable to preseve the cashe between calls to the function
    param(
        [Parameter(Mandatory=$true)][string]$CVE
    )
    #Check the prefect cache for the CVE, if present return that
    if ($global:PrefetchCache.Contains($CVE)) {
        return $global:PrefetchCache[$CVE]
    }
    else {
        $Scores = cvsslookup -CVE $CVE
        $global:PrefetchCache[$CVE] = $Scores
        $global:PrefetchCache.count
        return $Scores
    }
}

Main
