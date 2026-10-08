environnement = "prod"
aws_region    = "ca-central-1"

reseau = {
  vpc_cidr           = "10.30.0.0/16" # VPC séparé de l'unitaire
  subnet_public_cidr = "10.30.0.0/24"
  subnet_prive_cidr  = "10.30.1.0/24"
  zone               = "ca-central-1a"
}

ssh_key_name = "ascender-prod" # clé DIFFÉRENTE de l'unitaire

rancher = {
  nom = "rancher-prod"
  ip  = "10.30.1.10"
}

# Même forme que l'unitaire : c'est ce qui garantit que l'unitaire ressemble à la prod.
# Pour de la haute disponibilité : 3 control planes par cluster, répartis sur 3 zones.
clusters = {
  "prod-01" = {
    labels = {
      kargo   = "true"
      domaine = "prod-01.mondomaine.local"
    }
    noeuds = {
      "prod-01-cp1" = { ip = "10.30.1.21", role = "controlplane" }
      "prod-01-w1"  = { ip = "10.30.1.22", role = "worker" }
    }
  }
  "prod-02" = {
    labels = {
      domaine = "prod-02.mondomaine.local"
    }
    noeuds = {
      "prod-02-cp1" = { ip = "10.30.1.31", role = "controlplane" }
      "prod-02-w1"  = { ip = "10.30.1.32", role = "worker" }
    }
  }
}
