# terraform/modules/ec2/outputs.tf
#
# WHY: Outputs expose internal values to the module caller.
# main.tf uses module.app.public_ip and module.monitor.public_ip
# when building the Ansible inventory file and Terraform outputs.

output "id" {
  description = "The EC2 instance ID (e.g. i-0abc1234)."
  value       = aws_instance.this.id
}

output "public_ip" {
  description = "The public IPv4 address of the instance."
  value       = aws_instance.this.public_ip
}

output "private_ip" {
  description = "The private IPv4 address (used for internal communication inside the VPC)."
  value       = aws_instance.this.private_ip
}
