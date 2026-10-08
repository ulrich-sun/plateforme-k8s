locals {
  nom = "plateforme-${var.environnement}"

  # Aplatit { cluster => { noeuds => { nom => {...} } } } en { nom => {..., cluster} }
  noeuds = merge([
    for nom_cluster, c in var.clusters : {
      for nom_noeud, n in c.noeuds : nom_noeud => merge(n, { cluster = nom_cluster })
    }
  ]...)
}

# Ubuntu 24.04 LTS officielle (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
}

module "reseau" {
  source = "../modules/reseau-aws"

  nom                = local.nom
  vpc_cidr           = var.reseau.vpc_cidr
  subnet_prive_cidr  = var.reseau.subnet_prive_cidr
  subnet_public_cidr = var.reseau.subnet_public_cidr
  zone               = var.reseau.zone
  outils_vpc_nom     = var.reseau.outils_vpc_nom
}

module "rancher" {
  source = "../modules/vm-aws"

  name               = var.rancher.nom
  private_ip         = var.rancher.ip
  instance_type      = var.tailles["rancher"].instance_type
  disk_gb            = var.tailles["rancher"].disk_gb
  ami_id             = data.aws_ami.ubuntu.id
  subnet_id          = module.reseau.subnet_prive_id
  security_group_ids = [module.reseau.security_group_id]
  key_name           = var.ssh_key_name
  tags               = { role = "rancher" }
}

module "noeuds" {
  source   = "../modules/vm-aws"
  for_each = local.noeuds

  name               = each.key
  private_ip         = each.value.ip
  instance_type      = var.tailles[each.value.role].instance_type
  disk_gb            = var.tailles[each.value.role].disk_gb
  ami_id             = data.aws_ami.ubuntu.id
  subnet_id          = module.reseau.subnet_prive_id
  security_group_ids = [module.reseau.security_group_id]
  key_name           = var.ssh_key_name
  tags               = { role = each.value.role, cluster = each.value.cluster }
}
