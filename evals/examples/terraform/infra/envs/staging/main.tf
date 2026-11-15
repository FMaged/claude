module "vm" {
  source   = "../../modules/hyperv-vm"
  for_each = var.vms

  name                = each.key
  os                  = each.value.os
  role                = each.value.role
  image               = each.value.image
  cpus                = each.value.cpus
  memory_gb           = each.value.memory_gb
  vlan_id             = each.value.vlan_id
  mac                 = each.value.mac
  image_store         = var.image_store
  vm_root             = var.vm_root
  switch_name         = var.switch_name
  domain              = var.domain
  ssh_authorized_keys = var.ssh_authorized_keys
}
