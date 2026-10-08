# Réseau d'un environnement :
#   - un VPC dédié (isolation unitaire / prod)
#   - un sous-réseau PUBLIC qui ne contient que la passerelle NAT
#   - un sous-réseau PRIVÉ pour Rancher et les nœuds (aucune IP publique)
#   - un peering avec le VPC « outils » pour qu'Ascender puisse joindre les machines

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "nom" { type = string }
variable "vpc_cidr" { type = string }
variable "subnet_prive_cidr" { type = string }
variable "subnet_public_cidr" { type = string }
variable "zone" { type = string }
variable "outils_vpc_nom" {
  description = "Tag Name du VPC outils (créé à l'étape 0)"
  type        = string
}

# ---------- VPC et sous-réseaux ----------

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = var.nom }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = var.nom }
}

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_public_cidr
  availability_zone = var.zone
  tags              = { Name = "${var.nom}-public" }
}

resource "aws_subnet" "prive" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.subnet_prive_cidr
  availability_zone = var.zone
  tags              = { Name = "${var.nom}-prive" }
}

# Sortie Internet des nœuds (images, charts, scripts d'installation).
# Coût : une passerelle NAT est facturée à l'heure + au Go, même au repos.
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "${var.nom}-nat" }
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = { Name = var.nom }
  depends_on    = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = { Name = "${var.nom}-public" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "prive" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }
  tags = { Name = "${var.nom}-prive" }
}

resource "aws_route_table_association" "prive" {
  subnet_id      = aws_subnet.prive.id
  route_table_id = aws_route_table.prive.id
}

# ---------- Peering avec le VPC outils (Ascender) ----------

data "aws_vpc" "outils" {
  tags = { Name = var.outils_vpc_nom }
}

data "aws_route_table" "outils" {
  vpc_id = data.aws_vpc.outils.id
  filter {
    name   = "tag:Name"
    values = ["${var.outils_vpc_nom}-public"]
  }
}

resource "aws_vpc_peering_connection" "outils" {
  vpc_id      = data.aws_vpc.outils.id
  peer_vpc_id = aws_vpc.this.id
  auto_accept = true # même compte et même région
  tags        = { Name = "outils-vers-${var.nom}" }
}

resource "aws_route" "outils_vers_env" {
  route_table_id            = data.aws_route_table.outils.id
  destination_cidr_block    = aws_vpc.this.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.outils.id
}

resource "aws_route" "env_vers_outils" {
  route_table_id            = aws_route_table.prive.id
  destination_cidr_block    = data.aws_vpc.outils.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.outils.id
}

# ---------- Pare-feu ----------

resource "aws_security_group" "noeuds" {
  name        = "${var.nom}-noeuds"
  description = "Rancher et noeuds Kubernetes de ${var.nom}"
  vpc_id      = aws_vpc.this.id

  # Tout le trafic interne à l'environnement : etcd, API, kubelet, Cilium (VXLAN 8472/udp),
  # enregistrement des nœuds auprès de Rancher (443), etc.
  ingress {
    description = "Interne a l'environnement"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  # Depuis Ascender : SSH (Ansible), API Kubernetes de Rancher (6443), interface Rancher (443)
  dynamic "ingress" {
    for_each = { ssh = 22, https = 443, kube = 6443 }
    content {
      description = "Depuis outils : ${ingress.key}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [data.aws_vpc.outils.cidr_block]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.nom}-noeuds" }
}

output "vpc_id" { value = aws_vpc.this.id }
output "subnet_prive_id" { value = aws_subnet.prive.id }
output "security_group_id" { value = aws_security_group.noeuds.id }
