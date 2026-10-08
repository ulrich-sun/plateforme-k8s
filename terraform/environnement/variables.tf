variable "environnement" {
  description = "unitaire ou prod"
  type        = string

  validation {
    condition     = contains(["unitaire", "prod"], var.environnement)
    error_message = "environnement doit valoir « unitaire » ou « prod »."
  }
}

variable "aws_region" {
  type    = string
  default = "ca-central-1"
}

variable "reseau" {
  type = object({
    vpc_cidr           = string
    subnet_prive_cidr  = string
    subnet_public_cidr = string
    zone               = string
    outils_vpc_nom     = optional(string, "plateforme-outils")
  })
}

variable "ssh_key_name" {
  description = "Nom de la paire de clés EC2 (clé publique d'Ascender pour cet environnement)"
  type        = string
}

variable "tailles" {
  description = "Type d'instance et disque par rôle"
  type = map(object({
    instance_type = string
    disk_gb       = number
  }))
  default = {
    rancher      = { instance_type = "t3.xlarge", disk_gb = 80 } # 4 vCPU / 16 Go
    controlplane = { instance_type = "t3.large", disk_gb = 60 }  # 2 vCPU / 8 Go
    worker       = { instance_type = "t3.xlarge", disk_gb = 100 }
  }
}

variable "rancher" {
  description = "L'instance qui héberge le Rancher de cet environnement"
  type = object({
    nom = string
    ip  = string
  })
}

variable "clusters" {
  description = <<-EOT
    Les clusters de l'environnement. C'est LA source de vérité :
    - les instances EC2 sont créées à partir d'ici,
    - Ansible crée les clusters dans Rancher à partir d'ici,
    - les labels deviennent les étiquettes que Fleet utilise pour le ciblage.
  EOT
  type = map(object({
    labels = map(string)
    noeuds = map(object({
      ip   = string
      role = string # controlplane | worker
    }))
  }))

  validation {
    condition = alltrue(flatten([
      for c in values(var.clusters) : [for n in values(c.noeuds) : contains(["controlplane", "worker"], n.role)]
    ]))
    error_message = "Chaque nœud doit avoir role = controlplane ou worker."
  }

  validation {
    # Rappel etcd : 2 control planes = 0 panne tolérée ET deux fois plus de risques.
    condition = alltrue([
      for c in values(var.clusters) : length([for n in values(c.noeuds) : n if n.role == "controlplane"]) != 2
    ])
    error_message = "Un cluster ne doit pas avoir exactement 2 control planes (etcd). Utilisez 1 ou 3."
  }
}
