output "vms" {
  description = "Each VM's FQDN and reported IPv4 addresses."
  value       = { for name, vm in module.vm : name => { fqdn = vm.fqdn, ipv4 = vm.ipv4 } }
}
