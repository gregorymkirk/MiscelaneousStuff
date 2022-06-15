param (
    [Parameter()][String]$lookup
)

Write-host $lookup
$keyfile= "~\.ssh\id_rsa.pub"
$awsprofile="govca"
$key=get-content -Path $keyfile

import-module AWS.Tools.Common
import-module AWS.Tools.EC2
import-Module AWS.Tools.EC2InstanceConnect

Initialize-AWSDefaultConfiguration -ProfileName $awsprofile


if ($lookup -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' ) {
    write-host "Looking up by Ip Address"
    $instance=(Get-EC2Instance -Filter @(@{name="private-ip-address";values=$lookup})).Instances
    $instance
}
elseif ($lookup -match 'i-[a-z0-9]{17}') {
    Write-Host "Looking up by Instance ID"
    $filter = New-Object Amazon.EC2.Model.Filter -Property @{Name = "v"; Values = $lookup}
x
    $instance=(Get-Ec2Instance -InstanceId $Filter).instances
    $instance
}
else {
    write-host "$Lookup does not match pattern for InstanceId or IP address"
    exit
}

Send-EC2ICSSHPublicKey `
    -InstanceId $instance.InstanceId `
    -AvailabilityZone $instance.placement.AvailabilityZone `
    -InstanceOSUser "ec2-user" `
    -SSHPublicKey $key

ssh -i $keyfile ec2-user@$($instance.PrivateIpAddress)