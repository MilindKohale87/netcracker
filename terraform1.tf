# get information about the region we are operating in
data "aws_region" "this" {}

data "aws_ami" "centos_image" {
  most_recent = true
  owners      = ["aws-marketplace"]

  filter {
    name   = "name"
    values = ["CentOS-7-2111-20220825_1.x86_64-d9a3032a-921c-4c6d-b150-bde168105e42"]
  }

}

data "aws_ami" "ubuntu_image" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server*"]
  }

}


data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["assignment_vpc"]
  }
}



data "aws_subnet" "public_subnet" {
  filter {
    name   = "tag:Name"
    values = ["public_subnet_1a"]
  }
}

data "aws_subnet" "private_subnet" {
  filter {
    name   = "tag:Name"
    values = ["private_subnet_1b"]
  }
}



resource "aws_iam_role" "role" {
  name = "${var.service_name}-test"
  assume_role_policy = jsonencode(
    {
      "Version" : "2012-10-17",
      "Statement" : [
        {
          "Action" : "sts:AssumeRole",
          "Principal" : {
            "Service" : "ec2.amazonaws.com"
          },
          "Effect" : "Allow",
          "Sid" : ""
        }
      ]
    }
  )
  tags = merge({
    "Name" = "${var.service_name}-test",
    }
  )
}

resource "aws_iam_instance_profile" "profile" {
  name = "${var.service_name}-test"
  role = aws_iam_role.role.name
}

# ---- attach the basic AWS managed SSM EC2 policies ---------------------------
resource "aws_iam_role_policy_attachment" "amzn_ssm_instance_core" {
  role       = aws_iam_role.role.id
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

##---------- server security group --------##
resource "aws_security_group" "test" {
  name        = "${var.service_name}-test"
  description = "Manage access to server"
  vpc_id      = data.aws_vpc.vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge({
    "Name" = "${var.service_name}-test"
    }
  )
}

## Ec2 instance primary.
resource "aws_instance" "primary" {
  ami                  = data.aws_ami.centos_image.image_id
  iam_instance_profile = aws_iam_instance_profile.profile.name
  root_block_device {
    volume_size = var.instance_root_disc
  }

  user_data = <<EOF
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash

exec > >(tee /var/log/user-data.log)
exec 2>&1

yum clean metadata && yum update -y

sudo hostnamectl set-hostname centos8.local
sudo echo "centos8.local" >> /etc/hostname
sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl status amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
EOF

  vpc_security_group_ids = [
    aws_security_group.test.id
  ]
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.public_subnet.id
  tags = merge({
    "Name" = "${var.service_name}_centos_test"
  })
}

## Ec2 instance secondary.
resource "aws_instance" "secondary" {
  ami                  = data.aws_ami.ubuntu_image.image_id
  iam_instance_profile = aws_iam_instance_profile.profile.name
  root_block_device {
    volume_size = var.instance_root_disc
  }

  user_data = <<EOF
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash

exec > >(tee /var/log/user-data.log)
exec 2>&1

sudo hostname u21.local
sudo echo "u21.local" >> /etc/hostname
sudo snap switch --channel=candidate amazon-ssm-agent
sudo systemctl start snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl stop snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo systemctl status snap.amazon-ssm-agent.amazon-ssm-agent.service
sudo snap install amazon-ssm-agent --classic
sudo snap list amazon-ssm-agent
sudo snap start amazon-ssm-agent
sudo snap services amazon-ssm-agent
EOF

  vpc_security_group_ids = [
    aws_security_group.test.id
  ]
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.public_subnet.id
  tags = merge({
    "Name" = "${var.service_name}_ubuntu_test"
  })
}


## Ec2 instance ansible.
resource "aws_instance" "ansible" {
  ami                  = data.aws_ami.centos_image.image_id
  iam_instance_profile = aws_iam_instance_profile.profile.name
  root_block_device {
    volume_size = var.instance_root_disc
  }

  user_data = <<EOF
Content-Type: multipart/mixed; boundary="//"
MIME-Version: 1.0

--//
Content-Type: text/cloud-config; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="cloud-config.txt"

#cloud-config
cloud_final_modules:
- [scripts-user, always]

--//
Content-Type: text/x-shellscript; charset="us-ascii"
MIME-Version: 1.0
Content-Transfer-Encoding: 7bit
Content-Disposition: attachment; filename="userdata.txt"

#!/bin/bash

exec > >(tee /var/log/user-data.log)
exec 2>&1

yum clean metadata && yum update -y

sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
sudo systemctl status amazon-ssm-agent
sudo systemctl enable amazon-ssm-agent
sudo systemctl start amazon-ssm-agent
sudo yum -y install epel-repo
sudo yum -y update
sudo yum -y install ansible
ansible --version
EOF

  vpc_security_group_ids = [
    aws_security_group.test.id
  ]
  instance_type = var.instance_type
  subnet_id     = data.aws_subnet.public_subnet.id
  tags = merge({
    "Name" = "ansible_host"
  })
}

