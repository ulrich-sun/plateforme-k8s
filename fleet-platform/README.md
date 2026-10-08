# Socle de plateforme (déployé par Fleet)

Chaque dossier contenant un `fleet.yaml` devient un **bundle**. Chaque Rancher (unitaire, prod)
a un GitRepo `socle-plateforme` qui pointe ici et cible **tous** ses clusters.

| Bundle | Dépend de | Où |
|---|---|---|
| `00-cert-manager` | — | tous les clusters |
| `10-traefik` | cert-manager | tous les clusters |
| `20-monitoring` | — | tous les clusters |
| `30-argocd` | cert-manager, traefik | clusters étiquetés `kargo=true` |
| `40-kargo` | argocd, cert-manager | clusters étiquetés `kargo=true` |

**Ce qui n'est PAS ici** : Cilium. C'est le réseau des pods, il est choisi à la création du
cluster (`ansible/roles/rancher_cluster/templates/cluster.yaml.j2`).

## Étiquettes disponibles pour le ciblage

| Étiquette | Origine | Exemple |
|---|---|---|
| `env` | environnement (Ansible) | `unitaire`, `prod` |
| `kargo` | tfvars Terraform | `true` |
| `domaine` | tfvars Terraform | `unit-01.lab.local` |

Utilisables dans les valeurs Helm : `${ .ClusterLabels.domaine }`, `${ .ClusterName }`.

## Promotion du socle

1. Modifier un bundle sur `main` → déployé immédiatement en **unitaire**.
2. Valider sur les clusters unitaires.
3. `git tag plateforme-vX.Y.Z && git push --tags`
4. Mettre `fleet_platform_revision: plateforme-vX.Y.Z` dans `ansible/config/prod.yml`.
5. Lancer « [prod] 30 - Installer Rancher » dans Ascender → le GitRepo prod suit le nouveau tag.
