# ÉTAPE 0 — lancée UNE fois depuis votre poste : le VPC « outils » et l'instance Ascender.
# Ascender est le seul élément exposé (en HTTPS, et uniquement à votre IP).

terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  # Même bucket S3 que les environnements, avec une clé dédiée.
  backend "s3" {
    key          = "outils/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    # bucket et region : terraform init -backend-config="bucket=..." -backend-config="region=..."
  }
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "zone" {
  type    = string
  default = "us-east-1a"
}
variable "vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}
variable "ip_admin" {
  description = "Votre IP publique en /32, seule autorisée à joindre Ascender"
  type        = string
}
variable "ssh_key_name" {
  description = "Paire de clés EC2 de VOTRE poste (pour l'étape 0)"
  type        = string
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = { projet = "plateforme-k8s", environnement = "outils", gere-par = "terraform" }
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

resource "aws_vpc" "outils" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "plateforme-outils" } # retrouvé par nom par les environnements
}

resource "aws_internet_gateway" "outils" {
  vpc_id = aws_vpc.outils.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.outils.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, 0)
  availability_zone       = var.zone
  map_public_ip_on_launch = true
  tags                    = { Name = "plateforme-outils-public" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.outils.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.outils.id
  }
  # Les routes vers les VPC unitaire/prod sont ajoutées par la racine « environnement »
  tags = { Name = "plateforme-outils-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ascender" {
  name   = "ascender"
  vpc_id = aws_vpc.outils.id

  ingress {
    description = "Interface Ascender"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
  }
  ingress {
    description = "SSH administrateur"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ip_admin]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "ascender" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.xlarge" # 4 vCPU / 16 Go : confortable pour Ascender sur K3s
  subnet_id              = aws_subnet.public.id
  private_ip             = cidrhost(cidrsubnet(var.vpc_cidr, 8, 0), 10)
  vpc_security_group_ids = [aws_security_group.ascender.id]
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = 80
    volume_type = "gp3"
    encrypted   = true
  }
  metadata_options {
    http_tokens = "required"
  }
  tags = { Name = "ascender" }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_eip" "ascender" {
  instance = aws_instance.ascender.id
  domain   = "vpc"
}

output "ascender_ip_publique" {
  value = aws_eip.ascender.public_ip
}

output "ascender_ip_privee" {
  value = aws_instance.ascender.private_ip
}
