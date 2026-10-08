# Une instance EC2 avec une IP privée FIXE (choisie dans les tfvars).
# IP fixe = inventaire stable, entrées DNS stables, et pas de surprise après un redémarrage.

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

variable "name" { type = string }
variable "instance_type" { type = string }
variable "ami_id" { type = string }
variable "subnet_id" { type = string }
variable "private_ip" { type = string }
variable "security_group_ids" { type = list(string) }
variable "key_name" { type = string }
variable "disk_gb" { type = number }
variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  private_ip             = var.private_ip
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name

  root_block_device {
    volume_size           = var.disk_gb
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  metadata_options {
    http_tokens = "required" # IMDSv2 obligatoire (bonne pratique de sécurité)
  }

  # Le nom d'hôte de l'OS suit le tag Name (Ansible le fixe aussi, par sécurité)
  user_data = <<-EOF
    #cloud-config
    hostname: ${var.name}
    preserve_hostname: false
  EOF

  tags = merge(var.tags, { Name = var.name })

  lifecycle {
    # Une nouvelle AMI Ubuntu ne doit pas détruire les nœuds existants
    ignore_changes = [ami, user_data]
  }
}

output "name" {
  value = aws_instance.this.tags["Name"]
}

output "ip" {
  value = aws_instance.this.private_ip
}

output "id" {
  value = aws_instance.this.id
}
