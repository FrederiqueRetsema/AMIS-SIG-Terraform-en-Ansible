#!/bin/bash

# Ansible heeft zowel op de config-machine als op de remote machine Python nodig, daarnaast gaat het hier om web services dus installeer httpd.
# De ${websitetext} komt vanuit Terraform, zie resource.tf

yum -y install python httpd
systemctl start httpd
rm /etc/httpd/conf.d/welcome.conf
echo "<html><p>${websitetext}</p></html>" > /var/www/html/index.html
systemctl restart httpd
systemctl enable httpd

# Zet de firewall open voor poort 80
setenforce 0
firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --reload
setenforce 1

# Voeg user ansible toe tbv de ansible opdrachten. Zorg ervoor dat sudo bij ansible niet om een password vraagt
adduser ansible -G wheel
echo -e "%ansible\tALL=(ALL)\tALL\tNOPASSWD:ALL" >> ./sudoers
 
# De default voor password authenticatie met ssh is uit. We hebben het echter nodig voor onderstaande ssh-copy-id
# opdracht:
cat /etc/ssh/sshd_config | sed 's/PasswordAuthentication\ no/PasswordAuthentication\ yes/' > /tmp/ssh_config
cp /tmp/ssh_config /etc/ssh/sshd_config
systemctl restart sshd

