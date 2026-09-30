# terraform/modules/ec2/variables.tf
#
# WHY: These are the inputs to the EC2 module.
# By declaring them here we document what the module needs and allow
# the caller (main.tf) to pass different values for each server.

variable "name" {
  description = "Name tag for the EC2 instance."
  type        = string
}

variable "ami_id" {
  description = "AMI ID to launch (provided by the Ubuntu data source in main.tf)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type (e.g. t3.small, t3.micro)."
  type        = string
}

variable "key_name" {
  description = "Name of the AWS key pair used to access the instance."
  type        = string
}

variable "security_group_id" {
  description = "ID of the security group to attach to this instance."
  type        = string
}

variable "role" {
  description = "Logical role of this server (app or monitor) – used as a tag."
  type        = string
}
