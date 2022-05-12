# A Powershell script to simplify using instance connect.
# You must have created a publick key pair.  CHange $key on line 7 if you re not using the defualt key names.
# Yuu will also need the command line SSH client (Open SSH, )installed and in your path, or modiffy line 28 accordingly
param (
    [Parameter()][String]$lookup
)
$key= "~\.ssh\id_rsa.pub"

import-module AWS.Tools.Common
import-module AWS.Tools.EC2
import-Module AWS.Tools.EC2InstanceConnect

if ($lookup -match '^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$' ) {
    write-host "Looking up by Ip Address"
    $instance=(Get-Ec2Instance -Filter "private-ip-address=$instance").instances
}
elseif ($lookup -match 'i-[a-z0-9]{17}') {
    Write-Host "Looking up by Instance ID"
    $instance=(Get-Ec2Instance -InstanceId $lookup).instances
}

Send-EC2ICSSHPublicKey `
    -InstanceId $instance.Instances.InstanceId `
    -AvailabilityZone $instance.Instances.placement.AvailabilityZone `
    -InstanceOSUser "ec2-user" `
    -SSHPublicKey $key

ssh -i $key ec2-user@$($instance.Instances.PrivateIpAddress)