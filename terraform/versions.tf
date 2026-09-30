# terraform/versions.tf
#
# WHY THIS FILE EXISTS:
# Pinning provider versions prevents a surprise breaking change when HashiCorp
# releases a new provider version.  Without version constraints, `terraform init`
# could download a newer provider that behaves differently.
#
# The S3 + DynamoDB backend block is commented out.
# WHY: for local development you don't need remote state.
# In a team / production setup, enable it so everyone shares the same state file
# and state locking prevents two engineers from running `apply` simultaneously.

terraform {
  required_version = ">= 1.6"

  required_providers {
    # AWS provider – manages all AWS resources (EC2, security groups, key pairs, etc.)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.66"
    }
    # local provider – writes the Ansible inventory file to the filesystem.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    # null provider – used to run Ansible via a local-exec provisioner.
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  # ── Remote backend (enable for team / production use) ─────────────────────
  # Uncomment this block and run `terraform init` again to migrate local state.
  # Prerequisites: create an S3 bucket and a DynamoDB table (attribute LockID, type S).
  #
  # backend "s3" {
  #   bucket         = "your-terraform-state-bucket"
  #   key            = "devops-demo/terraform.tfstate"
  #   region         = "ap-south-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-lock"
  # }
}
