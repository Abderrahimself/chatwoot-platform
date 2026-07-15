output "k3s_node_ip" {
  description = "DHCP-assigned IP of the single-node k3s VM."
  value       = try(libvirt_domain.control.network_interface[0].addresses[0], null)
}

output "k3s_node_ssh" {
  description = "SSH command for the single-node k3s VM."
  value       = try("ssh abdo@${libvirt_domain.control.network_interface[0].addresses[0]}", null)
}
