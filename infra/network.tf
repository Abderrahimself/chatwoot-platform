resource "libvirt_network" "platform" {
  name      = "platform-net"
  mode      = "nat"
  domain    = "platform.local"
  addresses = ["10.17.3.0/24"]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled    = true
    local_only = true
  }
}
