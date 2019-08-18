Function Out-UTF8NoBOM {
# Out-File prior to PSversion 6 (aka powershell core) includes the BOM character at the start of UTF8 files, 
# which many programs (like Terraform) do not accept.    
# accepts a string containing content, and an absolute path & filename (e.g c:\mydir\myfile.txt),
# and writes a UTF-8 file with no BOM>
# if your script will only run on versions 6 or later (i.e. PowerShell Core) then this function is not necessary, 
# but using it allows backwards compatibility with older versions of powershell (a.k.a. Windows Powershell).

#
# WARNING: Function does NOT check for filename compliance (e.g reserved words, reserved characters etc) or valid paths. 
# Ref: fixing the BOM prepended to the win UTF8 file https://stackoverflow.com/questions/5596982/using-powershell-to-write-a-file-in-utf-8-without-the-bom
    Param ( [string] $Filename,
            [array] $Content
            )
     if ( $ver -lt 6 ){
       $File = New-Object System.Text.UTF8Encoding $False
       [system.IO.File]::WriteAllLines( $Filename, $Content, $File)
     }
     else {
     out-file -FilePath $Filename -Encoding UTF8NoBOM
     }
}
