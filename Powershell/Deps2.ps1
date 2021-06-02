Function InstallDeps{
    # Accepts a list of modules, checks to see if they are installed, if not installs them 
    # Then imports the modules.  Returns false if any module fails to install or load.
    Param([Object]$ModuleList)
    Write-Host $Modulelist

    If ($ModuleList -Match 'AWS.Tools'  ){
        If (!(get-installedmodule AWS.Tools.Installer)) {
            Try {
                install-module -Name 'AWS.Tools.Installer' -Force -AcceptLicense -AllowClobber -Repository PSGallery
                Import-Module 'AWS.Tools.Installer'}
            catch  {
             "Unable to install required Module AWS.Tools.Installer from PSGallery required for AWS.Tools modules" |Tee-Object -Path $errorlog -Append 
             return $False
             }  
        }
        else {
            Import-Module 'AWS.Tools.Installer'
        }
    }

    ForEach ($Module in $ModuleList){
        set-PSrepository -Name PSGallery -InstallationPolicy Trusted
        if (!(Get-InstalledModule -Name $Module )){ 
           Try {
               if ($Module -Like 'AWS.Tools'){ install-AWSToolsmodule -Name $Module -Force -AllowCLobber }
               else {install-module -Name $Module -Force -AcceptLicense -AllowClobber -Repository PSGallery}}
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
    Return $True
}

$modules = "Importexcel", "AWS.Tools.Common", "AWS.Tools.Ec2"
installdeps $modules
get-module