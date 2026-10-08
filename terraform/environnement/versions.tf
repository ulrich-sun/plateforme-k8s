terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  # Configuration partielle : le détail est dans backends/<environnement>.hcl
  #   terraform init -reconfigure -backend-config=backends/unitaire.hcl
  backend "s3" {}
}

# Identifiants AWS lus dans l'environnement :
# AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (injectés par le credential « Amazon Web Services » d'Ascender)
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      projet        = "plateforme-k8s"
      environnement = var.environnement
      gere-par      = "terraform"
    }
  }
}
