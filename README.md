# Plateforme Kubernetes multi-environnements sur AWS

Terraform crée les machines, Ansible les configure et les branche sur Rancher,
Fleet installe le socle sur chaque cluster, Argo CD et Kargo déploient les applications.
Le tout se pilote depuis **Ascender**.

## 1. Architecture

```
                         Internet (votre IP uniquement)
                                    │ 443
                     ┌──────────────▼──────────────┐
                     │ VPC outils  10.10.0.0/16    │
                     │ Ascender (K3s)              │  ← étape 0, une seule fois
                     └──────┬───────────────┬──────┘
                 peering    │               │    peering
          ┌─────────────────▼───┐       ┌───▼─────────────────┐
          │ VPC unitaire        │       │ VPC prod            │
          │ 10.20.0.0/16        │       │ 10.30.0.0/16        │
          │                     │       │                     │
          │ rancher-unitaire    │       │ rancher-prod        │
          │  └ Fleet → main     │       │  └ Fleet → tag      │
          │                     │       │                     │
          │ unit-01 (cp1 + w1)  │       │ prod-01 (cp1 + w1)  │
          │ unit-02 (cp1 + w1)  │       │ prod-02 (cp1 + w1)  │
          └─────────────────────┘       └─────────────────────┘
```

**11 instances EC2** : 1 Ascender, 2 Rancher, 8 nœuds (4 clusters × 2 nœuds).
Les instances des environnements sont en sous-réseau **privé** (sortie Internet via NAT).

## 2. Qui fait quoi

| Couche | Outil | Dossier | Rôle |
|---|---|---|---|
| 0 | Terraform | `terraform/` | VPC, NAT, security groups, instances EC2 |
| 1 | Ansible | `ansible/roles/os_base` | Socle OS (swap, noyau, horloge) |
| 2 | Ansible + Rancher | `ansible/roles/rke2_mgmt`, `rancher_*` | Rancher, création des clusters (avec **Cilium**), enregistrement des nœuds |
| 3 | Fleet | `fleet-platform/` | cert-manager, Traefik, monitoring, Argo CD, Kargo |
| 4 | Argo CD + Kargo | (dépôt applicatif, à venir) | Applications des équipes, promotion entre étapes |
| — | Ascender | `ascender/` | Interface, droits, enchaînement, approbation |

**La source de vérité est `terraform/environnement/envs/<env>.tfvars`** : la liste des clusters,
de leurs nœuds et de leurs **étiquettes**. Ansible lit la sortie Terraform (pas d'inventaire à la main),
crée les clusters dans Rancher avec ces étiquettes, et Fleet s'en sert pour savoir quoi installer où.

## 3. Le déroulé d'un « Construire l'environnement »

```
[prod seulement] Approbation humaine
      │
10 Provisionner      terraform apply → VPC, NAT, 5 instances, peering vers Ascender
      │
20 Préparer l'OS     swap off, modules noyau, sysctl, chrony
      │
30 Installer Rancher RKE2 mono-nœud → cert-manager → Rancher → GitRepo Fleet « socle-plateforme »
      │
40 Créer clusters    objet Cluster (provisioning.cattle.io) avec cni=cilium + étiquettes
      │              → commande d'enregistrement → exécutée sur chaque nœud avec son rôle
      │              → Rancher installe RKE2 → le cluster apparaît dans Fleet
      │              → Fleet déploie automatiquement le socle
50 Vérifier          attend que les clusters soient prêts, affiche étiquettes et bundles
```

Tout est **idempotent** : relancer le workflow sans rien changer ne casse rien.
Ajouter un cluster = ajouter un bloc dans les tfvars + relancer le workflow.

## 4. Étape 0 (une seule fois, depuis votre poste)

Prérequis : AWS CLI configuré, Terraform ≥ 1.10, Ansible.

```bash
# a) Bucket pour les états Terraform (nom unique au monde)
aws s3api create-bucket --bucket plateforme-k8s-tfstate-XXXX --region ca-central-1 \
  --create-bucket-configuration LocationConstraint=ca-central-1
aws s3api put-bucket-versioning --bucket plateforme-k8s-tfstate-XXXX \
  --versioning-configuration Status=Enabled
# → reportez ce nom dans terraform/environnement/backends/*.hcl

# b) Paires de clés EC2
aws ec2 import-key-pair --key-name mon-poste --public-key-material fileb://~/.ssh/id_ed25519.pub
ssh-keygen -t ed25519 -f ascender-unitaire -N "" && aws ec2 import-key-pair --key-name ascender-unitaire --public-key-material fileb://ascender-unitaire.pub
ssh-keygen -t ed25519 -f ascender-prod -N ""     && aws ec2 import-key-pair --key-name ascender-prod     --public-key-material fileb://ascender-prod.pub
# → les clés PRIVÉES ascender-* iront dans ascender/configuration/secrets.yml

# c) VPC outils + instance Ascender
cd terraform/outils
cp outils.tfvars.example outils.tfvars   # mettez votre IP
terraform init -backend-config="bucket=plateforme-k8s-tfstate-XXXX" -backend-config="region=ca-central-1"
terraform apply -var-file=outils.tfvars

# d) Préparer l'instance et récupérer l'installateur Ascender
cd ../../ansible
ansible-galaxy collection install -r requirements.yml
ansible-playbook -i <IP_PUBLIQUE>, -u ubuntu playbooks/00-bootstrap-outils.yml
# puis suivez le message affiché pour lancer l'installateur Ascender (type K3s)

# e) Construire et publier l'Execution Environment (voir ascender/execution-environment/)

# f) Configurer Ascender en code
cd ../ascender/configuration
cp secrets.yml.example secrets.yml && ansible-vault encrypt secrets.yml
export CONTROLLER_HOST=https://<IP_PUBLIQUE> CONTROLLER_USERNAME=admin CONTROLLER_PASSWORD=... CONTROLLER_VERIFY_SSL=false
ansible-playbook configurer-ascender.yml --ask-vault-pass
```

À partir de là, **tout passe par Ascender** : lancez « [unitaire] Construire l'environnement ».

## 5. Ce qu'il faut adapter avant le premier lancement

- [ ] Nom du bucket dans `terraform/environnement/backends/*.hcl`
- [ ] URL du dépôt Git dans `ansible/config/*.yml` et `ascender/configuration/vars.yml`
- [ ] `cluster_kubernetes_version` dans `ansible/config/*.yml` (version proposée par votre Rancher)
- [ ] Épingler les versions des charts (`version:` dans `fleet-platform/*/fleet.yaml`, `*_chart_version`)
- [ ] Image de l'Execution Environment dans `ascender/configuration/vars.yml`
- [ ] Créer le tag `plateforme-v1.0.0` avant de construire la prod
- [ ] Secret `kargo-valeurs` sur les clusters `kargo=true` (voir `fleet-platform/40-kargo/fleet.yaml`)

## 6. Accéder aux interfaces

Les Rancher et les clusters sont en réseau privé : on y accède **depuis le VPC outils**.
Le plus simple : un tunnel SSH par l'instance Ascender.

```bash
# 1. Tunnel : le port 8443 de votre poste mène au port 443 du Rancher unitaire
ssh -L 8443:10.20.1.10:443 ubuntu@<IP_PUBLIQUE_ASCENDER>

# 2. Rancher vérifie le nom d'hôte : faites pointer son nom vers votre poste
echo "127.0.0.1 rancher-unitaire.10.20.1.10.sslip.io" | sudo tee -a /etc/hosts

# 3. Navigateur : https://rancher-unitaire.10.20.1.10.sslip.io:8443
```

En entreprise : un VPN (AWS Client VPN) ou un ALB interne avec un vrai nom de domaine.

## 7. Limites assumées de ce socle (et comment les lever)

| Limite | Pourquoi | Pour la lever |
|---|---|---|
| 1 control plane par cluster | 2 nœuds demandés ; 2 etcd serait pire que 1 | 3 control planes sur 3 zones (Terraform refuse exactement 2) |
| Rancher sur 1 nœud | Simplicité | 3 nœuds RKE2 + `replicas: 3` |
| Une seule zone AWS | Coût, simplicité | Un sous-réseau privé par zone |
| Traefik en hostPort sur les workers | Pas de load balancer | NLB AWS devant les workers (Terraform) |
| Pas de stockage persistant | Pas de pilote CSI installé | Bundle Fleet `aws-ebs-csi-driver` + rôle IAM |
| Certificats auto-signés (sslip.io) | Pas de DNS d'entreprise | Route 53 + cert-manager avec Let's Encrypt |

## 8. Coût

11 instances (t3.large / t3.xlarge) + 2 passerelles NAT tournent en continu.
Pour un lab : détruisez l'unitaire le soir avec « [unitaire] 90 - Détruire » et reconstruisez-le
le matin ; c'est aussi le meilleur test que votre automatisation fonctionne vraiment.
