resource "libvirt_volume" "control_root" {
  name           = "control-root.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.ubuntu_base.id
  size           = 40 * 1024 * 1024 * 1024
  format         = "qcow2"
}
