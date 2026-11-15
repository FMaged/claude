variable "name" {
  description = "VM name in Hyper-V, also the guest hostname."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,14}$", var.name))
    error_message = "name must be lowercase, start with a letter, and be at most 15 characters (the NetBIOS limit)."
  }
}

variable "os" {
  description = "Guest OS family. Picks the secure boot template and the first-boot seed."
  type        = string

  validation {
    condition     = contains(["windows", "linux"], var.os)
    error_message = "os must be \"windows\" or \"linux\"."
  }
}

variable "role" {
  description = "Ansible group the VM belongs to, for example web or app."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9_]*$", var.role)) && !contains(["windows", "linux", "all", "ungrouped"], var.role)
    error_message = "role is an Ansible group name: lowercase letters, digits, and _, and not windows, linux, all, or ungrouped."
  }
}

variable "image" {
  description = "File name of the golden image in image_store, for example debian13-20261115-a1b2c3d.vhdx."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]+\\.vhdx$", var.image))
    error_message = "image must be a .vhdx file name, without a folder."
  }
}

variable "image_store" {
  description = "Folder on the Hyper-V host that holds the golden images Packer builds."
  type        = string
}

variable "vm_root" {
  description = "Folder on the Hyper-V host under which each VM gets its own folder for disks and the seed ISO."
  type        = string
}

variable "switch_name" {
  description = "Existing virtual switch on the host. The host owns it; this module only connects to it."
  type        = string
}

variable "domain" {
  description = "DNS domain of the VM. The FQDN is <name>.<domain>."
  type        = string
}

variable "cpus" {
  description = "Virtual processors."
  type        = number
  default     = 2

  validation {
    condition     = var.cpus >= 1 && var.cpus <= 16 && floor(var.cpus) == var.cpus
    error_message = "cpus must be a whole number between 1 and 16."
  }
}

variable "memory_gb" {
  description = "Static memory in GiB."
  type        = number
  default     = 4

  validation {
    condition     = var.memory_gb >= 1 && floor(var.memory_gb) == var.memory_gb
    error_message = "memory_gb must be a whole number of at least 1."
  }
}

variable "os_disk_gb" {
  description = "Size the OS disk is grown to after the copy. At least the image size."
  type        = number
  default     = 60

  validation {
    condition     = var.os_disk_gb >= 1
    error_message = "os_disk_gb must be at least 1."
  }
}

variable "vlan_id" {
  description = "Access VLAN on the switch port, or null for untagged."
  type        = number
  default     = null

  validation {
    condition     = var.vlan_id == null || (var.vlan_id >= 1 && var.vlan_id <= 4094 && floor(var.vlan_id) == var.vlan_id)
    error_message = "vlan_id must be a whole number between 1 and 4094."
  }
}

variable "mac" {
  description = "Static MAC, 12 hex digits in the locally administered range (starting 02). Only when a DHCP reservation needs it."
  type        = string
  default     = null

  validation {
    condition     = var.mac == null || can(regex("^02[0-9A-F]{10}$", var.mac))
    error_message = "mac must be 12 upper-case hex digits starting with 02, for example 02AB00000001."
  }
}

variable "admin_user" {
  description = "Account cloud-init creates on Linux guests. Ansible logs in as this user."
  type        = string
  default     = "ansible"
}

variable "ssh_authorized_keys" {
  description = "Public keys for admin_user on Linux guests."
  type        = list(string)
  default     = []
}

variable "time_zone" {
  description = "Windows time zone name for the unattend file."
  type        = string
  default     = "W. Europe Standard Time"
}
