#!/bin/bash

# Python is nodig voor ansible:
yum install python  ansible -y

# Maak een ansible user aan
adduser ansible

# Voeg de twee andere nodes toe aan de Ansible host tabel:
echo [web] >> /etc/ansible/hosts
echo ${first_ip_address} >> /etc/ansible/hosts
echo ${second_ip_address} >> /etc/ansible/hosts

# De default voor password authenticatie met ssh is uit. We hebben het echter nodig voor onderstaande ssh-copy-id
# opdracht:
cat /etc/ssh/sshd_config | sed 's/PasswordAuthentication\ no/PasswordAuthentication\ yes/' > /tmp/ssh_config
cp /tmp/ssh_config /etc/ssh/sshd_config
systemctl restart sshd

# Niet vergeten:
# ssh-keygen 					<-- alle defaults aanhouden
# ssh-copy-id node1				<-- je vindt de IP-adressen in /etc/ansible/hosts
# ssh-copy-id node2
