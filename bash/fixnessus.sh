!#/bin/bash
## Script accepts a file with name, IP address and name of key pair as a parameter (this can be programatically extracted from AWS)
## Script then process each line, adding the nessus scan user to each host
## Script adds key based auth limted to the nessus IP ranges, and adds the nessus user to sudoers with no password.

while IFS=, read -r name ip key
do
    echo "Name: $name  IP: $ip Key: ${key}.pem"
    # copy the key file to the host
    scp -i "~/.ssh/${key}.pem" nessus_authorized_keys ec2-user@$ip:~/nessus_authorized_keys
    # create the user, add the .ssh directeopry anc move thekey file there and rename it
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo useradd nessus'
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo mkdir /home/nessus/.ssh'
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo mv ~/nessus_authorized_keys /home/nessus/.ssh/authorized_keys'
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo chown nessus:nessus /home/nessus/.ssh/authorized_keys'
    # set correct permissions on key file 
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo chmod 600 /home/nessus/.ssh/authorized_keys'
    # backup and update the sudoers file, then reset permissions
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo cp /etc/sudoers /etc/sudoers.bak'
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip  'sudo chmod 660 /etc/sudoers'
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip "sudo echo 'nessus    ALL=(ALL)     NOPASSWD: ALL'| sudo EDITOR='tee -a' visudo"
    ssh -i "~/.ssh/${key}.pem" ec2-user@$ip 'sudo chmod 440 /etc/sudoers'

done<$1
