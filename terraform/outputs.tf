# terraform/outputs.tf
#
# WHY THIS FILE EXISTS:
# Outputs print useful information after `terraform apply` completes.
# They also let other Terraform modules reference values from this one.

output "app_url" {
  description = "URL to reach the Node.js app via the Kubernetes NodePort."
  value       = "http://${module.app.public_ip}:30080"
}

output "nagios_url" {
  description = "URL to the Nagios web interface."
  value       = "http://${module.monitor.public_ip}/nagios4"
}

output "app_public_ip" {
  description = "Public IP of the app server (needed for SSH and Ansible ad-hoc commands)."
  value       = module.app.public_ip
}

output "monitor_public_ip" {
  description = "Public IP of the monitor server."
  value       = module.monitor.public_ip
}

output "ssh_app" {
  description = "SSH command to connect to the app server."
  value       = "ssh ubuntu@${module.app.public_ip}"
}

output "ssh_monitor" {
  description = "SSH command to connect to the monitor server."
  value       = "ssh ubuntu@${module.monitor.public_ip}"
}
