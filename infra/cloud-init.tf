locals {
  node_name      = "k3s-node"
  node_domain    = "platform.local"
  node_fqdn      = "${local.node_name}.${local.node_domain}"
  ssh_public_key = trimspace(file(pathexpand("~/.ssh/id_ed25519.pub")))
}

resource "libvirt_cloudinit_disk" "control" {
  name = "control-cloudinit.iso"
  pool = "default"

  meta_data = <<-EOT
    instance-id: ${local.node_name}
    local-hostname: ${local.node_name}
  EOT

  user_data = <<-EOT
    #cloud-config
    hostname: ${local.node_name}
    fqdn: ${local.node_fqdn}
    manage_etc_hosts: true

    users:
      - name: abdo
        groups: [sudo]
        sudo: "ALL=(ALL) NOPASSWD:ALL"
        shell: /bin/bash
        lock_passwd: true
        ssh_authorized_keys:
          - ${local.ssh_public_key}

    ssh_pwauth: false
    disable_root: true
  EOT
}
