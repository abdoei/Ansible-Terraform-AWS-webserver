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

variable "subnet_prefix" {
  type = list(object({
    cidr_block = string
    name = string
  }))
  description = "Subnets CIDRs"
}

provider "aws" {
  region     = "us-east-1"
  access_key = var.access_key
  secret_key = var.secret_key
}

# create a VPC
resource "aws_vpc" "main_vpc" {
  cidr_block = "10.0.0.0/16"
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
  availability_zone = "us-east-1a"
  cidr_block        = var.subnet_prefix[0].cidr_block
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
    cidr_blocks = [aws_vpc.main_vpc.cidr_block, "0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block, "0.0.0.0/0"]
  }
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main_vpc.cidr_block, "0.0.0.0/0"]
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
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.sg1.id]
}

# Create an Elastic (static) IP
resource "aws_eip" "IP" {
  network_interface         = aws_network_interface.web_server_ni.id
  associate_with_private_ip = "10.0.1.50"

  depends_on = [aws_internet_gateway.gw, aws_instance.name]
}


output "public_IP" {
  value = aws_eip.IP.public_ip
}

# Create the Ubuntu server
resource "aws_instance" "name" {
  ami               = "ami-0e2c8caa4b6378d8c"
  instance_type     = "t2.micro"
  availability_zone = "us-east-1a"
  key_name          = "main-key"

  network_interface {
    network_interface_id = aws_network_interface.web_server_ni.id
    device_index         = 0
  }

  user_data = <<-EOF
                #!/bin/bash
                sudo apt update -y
                sudo apt install -y apache2
                sudo systemctl start apache2
                sudo systemctl enable apache2
                sudo bash -c 'echo "<!DOCTYPE html><html><title>AWS\&Terra</title><body><h1>Congrats</h1><p>You reached the website.</p></body></html>" > /var/www/html/index.html'
                EOF
  tags = {
    Name = "WEB_SERVER"
  }
}


