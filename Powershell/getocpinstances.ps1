param($profile)
import-module AWSpowershell.NetCore
Initialize-AWSDefaultConfiguration -ProfileName $profile 

$alias=get-iamAccountAlias

$content =''

#Get lsit of running (state code 16) OpenShift instances.
$list=(Get-EC2Instance -Region us-east-1 ).instances|? {$_.state.code -eq 16}|? {$_.Tag.Key -eq "Billing:Project" -and $_.Tag.value -eq "OpenShift"}
foreach ($instance in $list) {
    $ip = $instance.PrivateIpAddress
    $key = $instance.KeyName
    $name = $instance.Tags|?{$_.key -eq "Name"}|select -Expand Value
    $line = "$name,$ip,$key `n"
    Write-Host $line
    $content = $content +$line
    }

New-Item -path . -Name "$alias.csv" -ItemType File -Value $content