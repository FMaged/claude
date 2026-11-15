locals {
  is_windows = var.os == "windows"
  fqdn       = "${var.name}.${var.domain}"
  vm_dir     = "${var.vm_root}\\${var.name}"

  cloud_config = {
    hostname          = var.name
    fqdn              = local.fqdn
    preserve_hostname = false
    growpart          = { mode = "auto", devices = ["/"] }
    users = [{
      name                = var.admin_user
      groups              = ["sudo"]
      shell               = "/bin/bash"
      sudo                = "ALL=(ALL) NOPASSWD:ALL"
      lock_passwd         = true
      ssh_authorized_keys = var.ssh_authorized_keys
    }]
  }

  seed_files = local.is_windows ? {
    "Autounattend.xml" = templatefile("${path.module}/templates/Autounattend.xml.tftpl", {
      computer_name = upper(var.name)
      time_zone     = var.time_zone
    })
    } : {
    "meta-data" = yamlencode({ "instance-id" = "${var.name}-${var.image}", "local-hostname" = var.name })
    "user-data" = "#cloud-config\n${yamlencode(local.cloud_config)}"
  }
}

data "hyperv_vhd" "image" {
  path = "${var.image_store}\\${var.image}"

  lifecycle {
    postcondition {
      # Not self.exists: it is inverted in provider 1.2.1.
      condition     = self.path != ""
      error_message = "Image ${var.image} is not in ${var.image_store} on the host."
    }
  }
}

data "hyperv_network_switch" "this" {
  name = var.switch_name

  lifecycle {
    postcondition {
      condition     = self.id == var.switch_name
      error_message = "Switch ${var.switch_name} is not on the host. The name is case sensitive."
    }
  }
}

# source and parent_path do not force a new disk, so an image change replaces the
# disk, the seed, and the VM through this.
resource "terraform_data" "image" {
  input = var.image
}

resource "hyperv_vhd" "os" {
  path   = "${local.vm_dir}\\${var.name}-os.vhdx"
  source = data.hyperv_vhd.image.path
  size   = var.os_disk_gb * 1024 * 1024 * 1024

  lifecycle {
    replace_triggered_by = [terraform_data.image]
  }
}

data "archive_file" "seed" {
  type        = "zip"
  output_path = "${path.root}/.seed/${var.name}.zip"

  dynamic "source" {
    for_each = local.seed_files
    content {
      filename = source.key
      content  = source.value
    }
  }
}

resource "hyperv_iso_image" "seed" {
  # cloud-init NoCloud looks for this label; the provider allows only upper case.
  volume_name               = local.is_windows ? "UNATTEND" : "CIDATA"
  source_zip_file_path      = data.archive_file.seed.output_path
  source_zip_file_path_hash = data.archive_file.seed.output_sha
  destination_iso_file_path = "${local.vm_dir}\\seed.iso"
  iso_media_type            = "dvdplusrw_duallayer"
  iso_file_system_type      = "iso9660|joliet"

  lifecycle {
    replace_triggered_by = [terraform_data.image]
    # Read once at first boot; a rebuild under a running VM changes nothing in the guest.
    ignore_changes = [source_zip_file_path_hash]
  }
}

resource "hyperv_machine_instance" "this" {
  name                   = var.name
  path                   = var.vm_root # Hyper-V adds <name>\, so the config sits next to the disks
  generation             = 2
  processor_count        = var.cpus
  static_memory          = true
  memory_startup_bytes   = var.memory_gb * 1024 * 1024 * 1024
  checkpoint_type        = "Disabled"
  automatic_start_action = "StartIfRunning"
  automatic_stop_action  = "ShutDown"
  state                  = "Running"
  notes                  = "Managed by Terraform."

  vm_firmware {
    enable_secure_boot   = "On"
    secure_boot_template = local.is_windows ? "MicrosoftWindows" : "MicrosoftUEFICertificateAuthority"

    boot_order {
      boot_type           = "HardDiskDrive"
      controller_number   = 0
      controller_location = 0
    }
  }

  hard_disk_drives {
    controller_type     = "Scsi"
    controller_number   = 0
    controller_location = 0
    path                = hyperv_vhd.os.path
  }

  dvd_drives {
    controller_number   = 0
    controller_location = 1
    path                = hyperv_iso_image.seed.resolve_destination_iso_file_path
  }

  network_adaptors {
    name                = "lan"
    switch_name         = data.hyperv_network_switch.this.name
    vlan_access         = var.vlan_id != null
    vlan_id             = var.vlan_id
    dynamic_mac_address = var.mac == null
    static_mac_address  = var.mac
    wait_for_ips        = true
  }

  integration_services = {
    "Guest Service Interface" = false
    "Heartbeat"               = true
    "Key-Value Pair Exchange" = true
    "Shutdown"                = true
    "Time Synchronization"    = true
    "VSS"                     = true
  }

  lifecycle {
    replace_triggered_by = [terraform_data.image]
  }
}
