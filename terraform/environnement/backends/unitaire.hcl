# État Terraform de l'unitaire dans S3 (bucket créé à l'étape 0, voir README).
# Jamais d'état local : les jobs Ascender tournent dans des conteneurs éphémères.
bucket       = "plateforme-k8s-tfstate-CHANGEZ-MOI" # nom de bucket unique au monde
key          = "environnements/unitaire.tfstate"
region       = "ca-central-1"
encrypt      = true
use_lockfile = true # verrou natif S3 (Terraform >= 1.10), plus besoin de DynamoDB
