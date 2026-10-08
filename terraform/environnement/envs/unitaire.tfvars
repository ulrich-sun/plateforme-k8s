environnement = "unitaire"
aws_region    = "ca-central-1"

reseau = {
  vpc_cidr           = "10.20.0.0/16"
  subnet_public_cidr = "10.20.0.0/24"
  subnet_prive_cidr  = "10.20.1.0/24"
  zone               = "ca-central-1a"
}

ssh_key_name = "ascender-unitaire" # paire de clés EC2 à créer avant (voir README)

rancher = {
  nom = "rancher-unitaire"
  ip  = "10.20.1.10"
}

# 2 clusters de 2 nœuds : 1 control plane (+ etcd) et 1 worker chacun.
clusters = {
  "unit-01" = {
    labels = {
      kargo   = "true"               # Argo CD + Kargo centralisés sur ce cluster
      domaine = "unit-01.lab.local"  # DNS *.unit-01.lab.local → IP du worker
    }
    noeuds = {
      "unit-01-cp1" = { ip = "10.20.1.21", role = "controlplane" }
      "unit-01-w1"  = { ip = "10.20.1.22", role = "worker" }
    }
  }
  "unit-02" = {
    labels = {
      domaine = "unit-02.lab.local"
    }
    noeuds = {
      "unit-02-cp1" = { ip = "10.20.1.31", role = "controlplane" }
      "unit-02-w1"  = { ip = "10.20.1.32", role = "worker" }
    }
  }
}
