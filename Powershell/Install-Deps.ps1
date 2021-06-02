
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