# terraform/variables.tf
#
# WHY THIS FILE EXISTS:
# Variables make the configuration reusable and safe.
# Instead of hard-coding your IP or key path, you set them in terraform.tfvars
# (which is git-ignored) so they never end up in version control.

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "ap-south-1" # Mumbai – change to the region closest to you.
}

variable "project" {
  description = "Short name used to prefix all AWS resource names (e.g. devops-proj)."
  type        = string
  default     = "devops-proj"
}

variable "instance_type" {
  description = "EC2 instance type for the app server."
  type        = string
  default     = "t3.small" # t3.small has 2 vCPU / 2 GB RAM – enough for k3s.
}

variable "public_key_path" {
  description = "Path to your RSA public key file (e.g. ~/.ssh/id_rsa.pub). Used to create the AWS key pair."
  type        = string
}

variable "private_key_path" {
  description = "Path to your RSA private key file (e.g. ~/.ssh/id_rsa). Used by Ansible to SSH into the instances."
  type        = string
}

variable "my_ip_cidr" {
  description = "Your public IP in CIDR notation (e.g. 203.0.113.4/32). Only this IP can SSH in. Run: curl ifconfig.me"
  type        = string
  # No default – you MUST set this.  Leaving it open (0.0.0.0/0) is a security risk.

  validation {
    condition     = can(cidrnetmask(var.my_ip_cidr)) && var.my_ip_cidr != "0.0.0.0/0"
    error_message = "The my_ip_cidr value must be a valid IPv4 CIDR block and cannot be 0.0.0.0/0."
  }
}

variable "run_ansible" {
  description = "If true, Terraform will automatically run ansible-playbook after creating the servers."
  type        = bool
  default     = true
}
