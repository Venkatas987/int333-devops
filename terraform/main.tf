# terraform/main.tf
#
# WHY THIS FILE EXISTS:
# This is the main infrastructure definition. It creates:
#   - An SSH key pair (so Terraform and Ansible can log in to the servers)
#   - A security group (firewall rules)
#   - Two EC2 instances via the reusable ec2 module:
#       app     – runs k3s (Kubernetes) + the Node.js app
#       monitor – runs Nagios Core
#   - A local_file with the Ansible inventory (server IPs)
#   - A null_resource that runs Ansible automatically (if run_ansible = true)
#
# RULE: Never run `terraform apply` without explicit permission.
#       Always run `terraform plan` first to review what will change.

# ── Provider configuration ────────────────────────────────────────────────────
provider "aws" {
  region = var.region

  # Default tags applied to every AWS resource.
  # WHY: makes it easy to find project resources in the AWS console and to
  #       set up cost allocation reports.
  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "Terraform"
      Env       = local.env
    }
  }
}

# ── Locals ────────────────────────────────────────────────────────────────────
locals {
  # terraform.workspace is "default" unless you've run `terraform workspace new staging`.
  # WHY: lets us use the same code for staging and production by selecting a workspace.
  env = terraform.workspace
}

# ── AMI lookup ────────────────────────────────────────────────────────────────
# WHY: AMI IDs differ by region and are updated frequently.  Using a data source
# means we always get the latest Ubuntu 22.04 LTS without hard-coding an ID.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical (official Ubuntu publisher)

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ── SSH Key Pair ──────────────────────────────────────────────────────────────
# WHY: Ansible needs to SSH into the EC2 instances.  We upload the public key
# to AWS and reference it when launching instances.
resource "aws_key_pair" "this" {
  key_name   = "${var.project}-${local.env}"
  public_key = file(pathexpand(var.public_key_path))
}

# ── Security Group ────────────────────────────────────────────────────────────
# WHY: A security group is AWS's firewall.  We only open the ports we actually use.
# Keeping SSH and the Nagios UI limited to your IP prevents brute-force attacks.
resource "aws_security_group" "main" {
  name        = "${var.project}-${local.env}-sg"
  description = "DevOps demo security group"

  # SSH – restricted to your IP only (never open to 0.0.0.0/0).
  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # BUG FIX B1: SSH between servers (self-referencing).
  # WHY: Ansible running on the monitor server also needs to SSH to the app server.
  # `self = true` means "allow traffic from other instances in this same security group".
  ingress {
    description = "SSH between servers in this SG"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    self        = true
  }

  # BUG FIX B1: ICMP (ping) between servers.
  # WHY: Nagios checks the app server with PING first.  Without this rule,
  # the PING check would always fail and Nagios would mark the host DOWN
  # even when the app is running fine.
  # protocol = "icmp", from_port = -1, to_port = -1 means "all ICMP".
  ingress {
    description = "ICMP (ping) between servers in this SG"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    self        = true
  }

  # BUG FIX B1: NodePort 30080 from within the security group.
  # WHY: The Nagios plugin contacts the app on port 30080.
  # Even though the port is already public (0.0.0.0/0 below), keeping a self
  # rule means it still works if the public rule is later removed.
  ingress {
    description = "App NodePort from within SG (monitor → app)"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    self        = true
  }

  # Nagios web UI (port 80) – restricted to your IP only.
  ingress {
    description = "Nagios UI from my IP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.my_ip_cidr]
  }

  # App NodePort – public so you can test the app from any browser.
  # WHY 30080: k3s/Kubernetes NodePort range is 30000-32767.
  #trivy:ignore:AVD-AWS-0107 Demo app is intentionally accessible on NodePort 30080 without a WAF
  ingress {
    description = "App NodePort (public)"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic so the servers can reach apt, GHCR, etc.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-${local.env}-sg"
  }
}

# ── App Server ────────────────────────────────────────────────────────────────
module "app" {
  source = "./modules/ec2"

  name              = "${var.project}-${local.env}-app"
  ami_id            = data.aws_ami.ubuntu.id
  instance_type     = var.instance_type
  key_name          = aws_key_pair.this.key_name
  security_group_id = aws_security_group.main.id
  role              = "app"
}

# ── Monitor Server ────────────────────────────────────────────────────────────
module "monitor" {
  source = "./modules/ec2"

  name              = "${var.project}-${local.env}-monitor"
  ami_id            = data.aws_ami.ubuntu.id
  instance_type     = "t3.micro" # Nagios needs less CPU than k3s.
  key_name          = aws_key_pair.this.key_name
  security_group_id = aws_security_group.main.id
  role              = "monitor"
}

# ── Ansible Inventory ─────────────────────────────────────────────────────────
# WHY: Ansible needs to know the IP addresses of the servers.
# Terraform writes a hosts.ini file after creating the servers so the IPs
# are always up to date.  hosts.ini is git-ignored (contains real IPs).
resource "local_file" "ansible_inventory" {
  # BUG FIX B1: pass private IPs so Nagios uses internal addresses (faster, free).
  content = templatefile("${path.module}/inventory.tpl", {
    app_ip             = module.app.public_ip
    app_private_ip     = module.app.private_ip
    monitor_ip         = module.monitor.public_ip
    monitor_private_ip = module.monitor.private_ip
    key_path           = pathexpand(var.private_key_path)
    env_name           = local.env
  })
  filename = "${path.module}/../ansible/inventory/hosts.ini"
}

# ── Run Ansible ───────────────────────────────────────────────────────────────
# WHY: The null_resource + local-exec provisioner lets Terraform trigger Ansible
# automatically after the servers are created.  Set run_ansible = false in
# terraform.tfvars if you prefer to run Ansible manually.
resource "null_resource" "ansible" {
  count = var.run_ansible ? 1 : 0

  # Re-run Ansible if the inventory changes (i.e. server IPs changed).
  triggers = {
    inventory = local_file.ansible_inventory.content
  }

  depends_on = [local_file.ansible_inventory]

  provisioner "local-exec" {
    # WHY --ssh-extra-args StrictHostKeyChecking=no: the first SSH connection to a
    # new server would otherwise prompt "Are you sure you want to connect?" and hang.
    # WHY interpreter bash: ensures the script runs under bash (not sh) which is
    # required in WSL and Linux environments for proper here-doc handling.
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      ansible-playbook -i ../ansible/inventory/hosts.ini \
        --private-key=${pathexpand(var.private_key_path)} \
        --ssh-extra-args='-o StrictHostKeyChecking=no' \
        ../ansible/site.yml
    EOT
    working_dir = path.module
  }
}
