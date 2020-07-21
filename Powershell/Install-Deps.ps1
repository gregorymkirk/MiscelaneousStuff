
##  usage:

   if (Installdeps $modules) {

        #...continue doing yoru stuff}
    }
    else{
        # ... error out
    }

# or

if (!(InstallDeps $ModuleList)){
    Write-Host "Unable to initialize required Powershell Modules, Exiting."
    Write-Host "Unable to initialize required Powershell Modules, Exiting." |out-file -FilePath $errorlog -Append 
    Exit 1
}







#Function




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