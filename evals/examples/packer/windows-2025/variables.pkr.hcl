variable "build_password" {
  type        = string
  sensitive   = true
  description = "Password of the build Administrator, used only during the build. Set PKR_VAR_build_password from a masked CI variable."

  validation {
    # It is written into the answer file as XML text.
    condition     = !can(regex("[<>&]", var.build_password))
    error_message = "The build_password must not contain <, >, or &."
  }
}

variable "git_sha" {
  type        = string
  description = "Short commit sha of this build. CI sets PKR_VAR_git_sha from CI_COMMIT_SHORT_SHA."

  validation {
    condition     = can(regex("^[0-9a-f]{7,12}$", var.git_sha))
    error_message = "The git_sha must be a short commit sha."
  }
}

variable "iso_url" {
  type        = string
  description = "Path or URL of the Windows Server 2025 install ISO."
}

variable "iso_checksum" {
  type        = string
  description = "Checksum of the install ISO, as sha256:<hex>."

  validation {
    condition     = can(regex("^sha256:[0-9a-f]{64}$", var.iso_checksum))
    error_message = "The iso_checksum must be sha256:<64 hex digits>, never none."
  }
}

variable "image_edition" {
  type        = string
  description = "The /IMAGE/NAME of the edition in install.wim, as Get-WindowsImage lists it."
}

variable "switch_name" {
  type        = string
  description = "Hyper-V switch with DHCP that the runner can reach on port 5985."
}

variable "image_store" {
  type        = string
  description = "Folder on the Hyper-V host that holds the golden images, the one Terraform's image_store names."

  validation {
    condition     = can(regex("^[A-Za-z]:\\\\", var.image_store))
    error_message = "The image_store must be an absolute Windows path, for example D:\\Images."
  }
}
