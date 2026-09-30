# terraform/inventory.tpl
#
# WHY THIS FILE EXISTS:
# Terraform uses this template to generate ansible/inventory/hosts.ini
# after creating the EC2 instances.  The $${var} expressions insert the
# real server IPs into the output file.
#
# BUG FIX B1: private_ip is now included so Nagios uses the VPC-internal
# address for its checks.  Internal traffic is free, faster, and doesn't
# depend on the public IP changing after a reboot.
#
# The generated file is git-ignored because it contains real server IPs.

[app]
app1 ansible_host=${app_ip} private_ip=${app_private_ip}

[monitor]
mon1 ansible_host=${monitor_ip} private_ip=${monitor_private_ip}

[all:vars]
# Connection settings used by every Ansible task.
ansible_user=ubuntu
ansible_ssh_private_key_file=${key_path}
ansible_ssh_common_args=-o StrictHostKeyChecking=no

# Custom variable – used by Puppet's env_label function and Nagios labels.
env_name=${env_name}
