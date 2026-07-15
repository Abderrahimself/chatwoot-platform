resource "libvirt_domain" "control" {
  name      = local.node_name
  memory    = 7168
  vcpu      = 4
  autostart = true

  cloudinit = libvirt_cloudinit_disk.control.id

  cpu {
    mode = "host-passthrough"
  }

  disk {
    volume_id = libvirt_volume.control_root.id
  }

  network_interface {
    network_id     = libvirt_network.platform.id
    hostname       = local.node_name
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
