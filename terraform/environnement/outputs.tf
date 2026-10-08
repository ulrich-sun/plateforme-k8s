# Le contrat entre Terraform et Ansible.
# Ansible lit cette sortie (terraform output -json inventaire) pour construire son inventaire.
output "inventaire" {
  value = {
    environnement = var.environnement
    rancher = {
      nom = module.rancher.name
      ip  = module.rancher.ip
    }
    clusters = {
      for nom_cluster, c in var.clusters : nom_cluster => {
        labels = c.labels
        noeuds = [
          for nom_noeud, n in c.noeuds : {
            nom  = module.noeuds[nom_noeud].name
            ip   = module.noeuds[nom_noeud].ip
            role = n.role
          }
        ]
      }
    }
  }
}
