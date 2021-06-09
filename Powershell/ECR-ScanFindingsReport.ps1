#ECR-ScanFindingsReport-Running v0.1
Param(
    [Alias("P")][string]$awsProfile
    )
Function Main {
    Initialize-AWSDefaults -ProfileName $awsProfile -Region us-gov-west-1
    $ModuleList= "ImportExcel","AWS.Tools.Common","AWS.Tools.ECR","AWS.Tools.IdentityManagement"
    InstallDeps $ModuleList
    $filename= "ECR-Scan-Findings.xlsx"
    Write-Host "Generating ECR Container Scan results for $account"
    $report = "Repository; Tags; Digest; Vulnerability; Severity; CVSS2_SCORE; package_name; package_version; Description`n"
    

    #Get a list of all running pods digests in a sorted list.
    $pods=kubectl get pods -A -o json|convertfrom-json -asHashTable
    $Digests = @()
    foreach($item in $pods.items){
        #FIXME Check to see if there is a digest first
        $Digests += ($item.status.containerStatuses.imageID.split("@")[1])
       }
    $Digests = $Digests|sort-object -Unique
    $report = "Repository; Tags; Digest; Vulnerability; Upstream Severity; CVSS2_Score; CVSS2_Sev;CVSS3_Score; CVSS3_Severity; package_name; package_version; Description`n"
    $ECRrepos = get-ecrrepository
    foreach ($repo in $ECRrepos){
        $images = Get-ECRImage -RepositoryName $repo.RepositoryName
        Foreach ($image in $images) {
            if ($Digests.Contains($image.ImageDigest)) {
                $findings = Get-ECRImageScanFinding -RepositoryName $repo.RepositoryName -ImageId_ImageDigest $image.ImageDigest
                foreach ($finding in $findings) {
                    foreach ($vulnerability in $finding.ImageScanFindings.Findings ){
                        $CVSS = $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('CVSS2_SCORE')]) 
                        if (!($CVSS)) {$CVSS = "N/A"}
                        if ($($Vulnerability.Name.StartsWith("CVE-"))){
                            $Scores= cvsslookup -CVE $($Vulnerability.Name)
                            $vuln = "$($repo.RepositoryName);$($image.ImageTag); $($image.ImageDigest); $($Vulnerability.Name); $($Vulnerability.Severity); $CVSS ; $($Scores.cvssV2severity); $($Scores.cvssV3Score); $($Scores.cvssV3severity); $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_name')]); $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_version')]);$($Vulnerability.Description)`n"
                        }
                        else {
                            $vuln = "$($repo.RepositoryName);$($image.ImageTag); $($image.ImageDigest); $($Vulnerability.Name); $($Vulnerability.Severity); $CVSS ; "" ;"";""; $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_name')]); $($Vulnerability.Attributes.Value[$Vulnerability.Attributes.key.indexof('package_version')]);$($Vulnerability.Description)`n"
                        }
			if ($vuln -ne $oldvuln) {$report += $vuln}
                        $oldvuln=$vuln
                    }
                }
            }
        }
    }
    $data = ConvertFrom-csv -Delimiter ';' -Inputobject $report
    Export-Excel -Inputobject $data -Path "./$filename"
}


Function InstallDeps{
    # Accepts a list of modules, checks to see if they are installed, if not installs them 
    # Then imports the modules.  Returns false if any module fails to install or load.
    # assign var : $ModuleList= "ImportExcel", "AWS.Tools.Common","AWS.Tools.Ec2","AWS.Tools.IdentityManagement"
    Param([Object]$ModuleList)
    ForEach ($Module in $ModuleList){
        set-PSrepository -Name PSGallery -InstallationPolicy Trusted
        if (!(Get-InstalledModule -Name $Module )){ 
           Try {install-module -Name $Module -Force -AcceptLicense -AllowClobber -Repository PSGallery -Scope Currentuser}
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
}$CVE=

Function cvsslookup {
    # We will return a hastable with CVSS 2 & 3 scores and severity ratings if it success
    # Otherwise we are going to return False.
    # Older vulnerabilities may not have a CVSS3 score or severity.   Not sure yet hwo this will handle that.
    param(
        [Parameter(Mandatory=$true)][string]$CVE
    )
    $CVE=$CVE.toupper()
    $baseurl= "https://services.nvd.nist.gov/rest/json/cve/1.0/"

    $req=$(invoke-webrequest "$baseurl$CVE")
    #only proceed if we got a good response
    if ($req.StatusCode -eq 200) {
        $result = $req.Content|out-string|convertfrom-json -AsHashtable
        $cvssV3score = $result.result.CVE_Items.impact.baseMetricV3.cvssV3.baseScore
        $cvssv3severity = $result.result.CVE_Items.impact.baseMetricV3.cvssV3.baseSeverity
        $cvssV2score = $result.result.CVE_Items.impact.baseMetricV2.impactScore
        $cvssV2severity = $result.result.CVE_Items.impact.baseMetricV2.severity 


        $scores = @{ 
            cvssV3Score = $cvssV3score ; 
            cvssV3severity = $cvssV3severity; 
            cvssV2Score = $cvssV2score ; 
            cvssV2severity = $cvssV2severity
        }
        return $scores

    }
    Else{
        #Return an error since API call failed
        #Maybe return the Web status code?
        return $false
    }
}

Main
