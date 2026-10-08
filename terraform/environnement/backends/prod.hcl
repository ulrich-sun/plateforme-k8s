# État de la prod : clé distincte. En entreprise, idéalement un bucket (voire un compte AWS)
# distinct, avec une politique IAM qui n'autorise que le credential « prod » d'Ascender.
bucket       = "plateforme-k8s-tfstate-CHANGEZ-MOI"
key          = "environnements/prod.tfstate"
region       = "ca-central-1"
encrypt      = true
use_lockfile = true
