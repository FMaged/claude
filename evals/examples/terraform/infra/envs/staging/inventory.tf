# Each host is in its OS group (connection settings) and its role group (group_vars/<role>.yml).
locals {
  vms   = values(module.vm)
  roles = distinct([for vm in local.vms : vm.role])

  inventory = {
    all = {
      children = merge(
        {
          for os in ["windows", "linux"] : os => {
            hosts = { for vm in local.vms : vm.fqdn => {} if vm.os == os }
          }
        },
        {
          for role in local.roles : role => {
            hosts = { for vm in local.vms : vm.fqdn => {} if vm.role == role }
          }
        },
      )
    }
  }
}

# Generated: Ansible reads this and never keeps its own list of hosts.
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../../../ansible/inventory/${basename(abspath(path.module))}.yml"
  file_permission = "0644"
  content         = yamlencode(local.inventory)
}
