# terraform/modules/ec2/main.tf
#
# WHY THIS IS A MODULE:
# A Terraform module is a reusable block of infrastructure.
# We use one module for both the app server and the monitor server.
# This avoids copy-pasting and ensures both servers are configured identically
# (same AMI, same security hardening) with only the size differing.

resource "aws_instance" "this" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [var.security_group_id]

  # WHY IMDSv2 (http_tokens = "required"):
  # IMDSv1 allows any process inside the instance to read AWS credentials from the
  # metadata API without authentication.  IMDSv2 requires a session token, which
  # prevents SSRF attacks from stealing the instance's IAM role credentials.
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_size = 20 # GB – enough for OS + k3s + images.
    volume_type = "gp3"
    # WHY encrypted: protects data at rest.  Without encryption, someone with
    # access to the EBS snapshot could read all your files.
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = var.name
    Role = var.role
  }

  # WHY ignore_changes on ami:
  # The root main.tf queries data.aws_ami.ubuntu for the latest Ubuntu 22.04 image.
  # When Canonical publishes a new release, Terraform would otherwise detect an AMI
  # change and force recreation (destroy and replace) of live instances.
  # This lifecycle rule keeps existing running instances intact.
  lifecycle {
    ignore_changes = [ami]
  }
}
