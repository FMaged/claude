output "name" {
  description = "VM name."
  value       = hyperv_machine_instance.this.name
}

output "fqdn" {
  description = "Name Ansible connects to. Kerberos needs the name, not the address."
  value       = local.fqdn
}

output "os" {
  description = "Guest OS family, windows or linux."
  value       = var.os
}

output "role" {
  description = "Ansible group."
  value       = var.role
}

output "ipv4" {
  description = "IPv4 addresses the guest reports through Key-Value Pair Exchange."
  value = [
    for ip in hyperv_machine_instance.this.network_adaptors[0].ip_addresses : ip
    if can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", ip))
  ]
}
