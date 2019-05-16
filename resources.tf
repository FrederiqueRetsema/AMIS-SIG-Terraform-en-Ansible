##################################################################################
# PROVIDERS
##################################################################################

provider "aws" {
  access_key = "${var.aws_access_key}"
  secret_key = "${var.aws_secret_key}"
  region     = "eu-west-1"
}

##################################################################################
# DATA
##################################################################################

data "aws_availability_zones" "available" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners = [679593333241]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}


##################################################################################
# RESOURCES
##################################################################################

# NETWORKING #
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  name   = "demo_beheer"

  cidr            = "10.0.0.0/16"
  azs             = "${data.aws_availability_zones.available.names}"
  public_subnets = ["10.0.0.0/24"]
  private_subnets = ["10.0.1.0/24"]
  assign_generated_ipv6_cidr_block="false" 
  enable_nat_gateway = "false" 
  single_nat_gateway = "false"
  enable_dns_hostnames = "true" 
  enable_dns_support = "true"
  public_subnet_tags = {
    Name = "demo-beheer-public"
  }
  vpc_tags = {
    Name = "demo-beheer-vpc"
  }
}

# SECURITY GROUPS #
resource "aws_security_group" "demo_sg" {
  name        = "demo_sg"
  vpc_id      = "${module.vpc.vpc_id}"

  #Allow HTTP from anywhere
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags {
    Name = "demo_sg"
  }
}

# INSTANCES #
resource "aws_instance" "demo_control" {
  ami           = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  subnet_id     = "${element(module.vpc.public_subnets,0)}" 
  vpc_security_group_ids = ["${aws_security_group.demo_sg.id}"]
  key_name        = "${var.key_name}"

  user_data = <<EOF
#!/bin/bash

# Python is nodig voor ansible, unzip voor terraform:
apt-get -y install python unzip

# Haal terraform op en unzip het
cd /home/ubuntu
curl https://releases.hashicorp.com/terraform/0.11.13/terraform_0.11.13_linux_amd64.zip --output /home/ubuntu/terraform.zip
unzip /home/ubuntu/terraform.zip

# Installeer de nieuwste versie van ansible (zie handleiding Ansible)
apt-get update
apt-get -y install software-properties-common
apt-add-repository --yes --update ppa:ansible/ansible
apt-get -y install ansible

# Maak een ansible user aan (voor wie dat prettig vindt ;-) ) 
adduser ansible

# Voeg de twee andere nodes toe aan de Ansible host tabel:
echo [web] >> /etc/ansible/hosts
echo ${element(aws_instance.demo_node.*.private_ip,0)} >> /etc/ansible/hosts
echo ${element(aws_instance.demo_node.*.private_ip,1)} >> /etc/ansible/hosts

# De default voor password authenticatie met ssh is uit. We hebben het echter nodig voor onderstaande ssh-copy-id
# opdracht:
cat /etc/ssh/sshd_config | sed 's/PasswordAuthentication\ no/PasswordAuthentication\ yes/' > /tmp/ssh_config
cp /tmp/ssh_config /etc/ssh/sshd_config
systemctl restart sshd

# Niet vergeten:
# ssh-keygen 					<-- alle defaults aanhouden
# ssh-copy-id node1				<-- je vindt de IP-adressen in /etc/ansible/hosts
# ssh-copy-id node2
EOF

  tags {
    Name = "demo-control-${count.index + 1}"
  }
}

resource "aws_instance" "demo_node" {
  count         = "${var.instance_count}"
  ami           = "${data.aws_ami.ubuntu.id}"
  instance_type = "t2.micro"
  subnet_id     = "${element(module.vpc.public_subnets,0)}" 
  vpc_security_group_ids = ["${aws_security_group.demo_sg.id}"]
  key_name        = "${var.key_name}"

  user_data = <<EOF
#!/bin/bash

# Ansible heeft zowel op de config-machine als op de remote machine Python nodig:
apt-get -y install python unzip

# Voeg user ansible toe tbv de ansible opdrachten
adduser ansible

# De default voor password authenticatie met ssh is uit. We hebben het echter nodig voor onderstaande ssh-copy-id
# opdracht:
cat /etc/ssh/sshd_config | sed 's/PasswordAuthentication\ no/PasswordAuthentication\ yes/' > /tmp/ssh_config
cp /tmp/ssh_config /etc/ssh/sshd_config
systemctl restart sshd

EOF

  tags {
    Name = "demo-node-${count.index + 1}"
  }
}
