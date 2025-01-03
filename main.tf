locals {
  key_pair_name = "main-key"

  ami           = "ami-0e2c8caa4b6378d8c"
  instance_type = "t2.micro"
  server_user   = "ubuntu"

  zone   = "us-east-1a"
  region = "us-east-1"

  private_ip    = "10.0.1.50"
  subnet_prefix = { cidr_block = "10.0.1.0/24", name = "prod_subnet" }
  main_vpc_cidr = "10.0.0.0/16"
}

variable "access_key" {
  description = "AWS Access Key"
  type        = string
  sensitive   = true
}

variable "secret_key" {
  description = "AWS Secret Key"
  type        = string
  sensitive   = true
}

provider "aws" {
  region     = local.region
  access_key = var.access_key
  secret_key = var.secret_key
}

# create a VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = local.main_vpc_cidr
  tags = {
    Name = "main-vpc"
  }
}

# create an internet gateway and link it to the vpc
resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.main_vpc.id
  tags = {
    Name = "prod-gw"
  }
}

# create a route table to route traffic to the internet gateway
resource "aws_route_table" "rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }
  tags = {
    "key" = "prod-rt"
  }
}

# create a subnet in the vpc
resource "aws_subnet" "sub1" {
  vpc_id            = aws_vpc.main_vpc.id
  availability_zone = local.zone
  cidr_block        = local.subnet_prefix.cidr_block
  tags = {
    Name = "prod-sub1"
  }
}

# associate the route table with the subnet
resource "aws_route_table_association" "ta" {
  subnet_id      = aws_subnet.sub1.id
  route_table_id = aws_route_table.rt.id
}

# Create security group to allow ports 22, 80, and 443
resource "aws_security_group" "sg1" {
  vpc_id = aws_vpc.main_vpc.id
  name   = "Allow_web_traffic"
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    Name = "Allow_Web"
  }
}

# Create a network interface with an ip in subnet of sub1
resource "aws_network_interface" "web_server_ni" {
  subnet_id       = aws_subnet.sub1.id
  private_ips     = [local.private_ip]
  security_groups = [aws_security_group.sg1.id]
}

# Create an Elastic (static) IP
resource "aws_eip" "IP" {
  network_interface         = aws_network_interface.web_server_ni.id
  associate_with_private_ip = local.private_ip

  depends_on = [aws_internet_gateway.gw]
}

# Create the Ubuntu server
resource "aws_instance" "apache_server" {
  ami               = local.ami
  instance_type     = local.instance_type
  availability_zone = local.zone
  key_name          = local.key_pair_name


  network_interface {
    network_interface_id = aws_network_interface.web_server_ni.id
    device_index         = 0
  }

  provisioner "remote-exec" {
    inline = ["sudo apt update -y",
      "echo 'Wait untill SSH is ready'"
    ]

    connection {
      type        = "ssh"
      user        = local.server_user
      private_key = file("${local.key_pair_name}.pem")
      host        = self.public_ip
    }
  }

  provisioner "local-exec" {
    command = "cd ansible && ansible-playbook -i ${self.public_ip}, --private-key ../main-key.pem apache.yaml"
  }

  depends_on = [aws_eip.IP]
  tags = {
    Name = "WEB_SERVER"
  }
}

output "public_IP" {
  value = aws_eip.IP.public_ip
}
