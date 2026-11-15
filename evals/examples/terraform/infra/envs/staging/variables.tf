variable "vms" {
  description = "VMs in this environment, keyed by VM name. The key becomes the Hyper-V name and the hostname."
  type = map(object({
    image     = string # golden image file name, for example win2025-20261115-a1b2c3d.vhdx
    os        = string # "windows" or "linux"
    role      = string # Ansible group, for example "web" or "db"
    cpus      = optional(number, 2)
    memory_gb = optional(number, 4)
    vlan_id   = optional(number)
    mac       = optional(string) # only when a DHCP reservation needs it
  }))

  validation {
    condition     = alltrue([for name, vm in var.vms : can(regex("^[a-z][a-z0-9-]{0,14}$", name))])
    error_message = "VM names must be lowercase, start with a letter, and be at most 15 characters (the NetBIOS limit)."
  }

  validation {
    condition     = alltrue([for vm in values(var.vms) : contains(["windows", "linux"], vm.os)])
    error_message = "os must be \"windows\" or \"linux\"."
  }

  validation {
    condition = alltrue([
      for vm in values(var.vms) :
      can(regex("^[a-z][a-z0-9_]*$", vm.role)) && !contains(["windows", "linux"], vm.role)
    ])
    error_message = "role is an Ansible group name: lowercase letters, digits, and _, and not windows or linux."
  }
}

variable "image_store" {
  description = "Folder on the Hyper-V host with the golden images."
  type        = string
}

variable "vm_root" {
  description = "Folder on the Hyper-V host for VM disks and seed ISOs."
  type        = string
}

variable "switch_name" {
  description = "Existing virtual switch the VMs connect to."
  type        = string
}

variable "domain" {
  description = "DNS domain of this environment's VMs."
  type        = string
}

variable "ssh_authorized_keys" {
  description = "Public keys for the Ansible user on Linux guests."
  type        = list(string)
}
