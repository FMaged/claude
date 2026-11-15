packer {
  required_version = ">= 1.11.0"
  required_plugins {
    hyperv = {
      source  = "github.com/hashicorp/hyperv"
      version = "= 1.1.5"
    }
    windows-update = {
      source  = "github.com/rgl/windows-update"
      version = "= 0.18.5"
    }
  }
}

locals {
  # win2025-20261115-a1b2c3d: the file name Terraform's vms map points at.
  image_name = "win2025-${formatdate("YYYYMMDD", timestamp())}-${var.git_sha}"
}

source "hyperv-iso" "win2025" {
  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vm_name              = local.image_name
  generation           = 2
  enable_secure_boot   = true
  secure_boot_template = "MicrosoftWindows"
  cpus                 = 4
  memory               = 8192
  disk_size            = 61440 # MB; Terraform can grow the copy, never shrink it
  switch_name          = var.switch_name
  headless             = true

  skip_export      = true # only the VHDX is needed; Terraform makes the VMs
  output_directory = "output/${local.image_name}"

  cd_content = {
    "Autounattend.xml" = templatefile("files/Autounattend.xml.pkrtpl", {
      edition  = var.image_edition
      password = var.build_password
    })
  }
  cd_label = "PACKER"

  # Generation 2 shows "Press any key to boot from CD or DVD" for a few seconds.
  boot_wait    = "1s"
  boot_command = ["a<wait>a<wait>a"]

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.build_password
  winrm_use_ntlm = true
  winrm_timeout  = "2h"

  shutdown_command = join(" && ", [
    # Schedule the shutdown first: the WinRM changes after it may end this session.
    "shutdown /s /t 10 /f /d p:4:1 /c Packer",
    "powershell -NoProfile -Command \"Remove-NetFirewallRule -Name PackerWinRM; Set-Item WSMan:\\localhost\\Service\\AllowUnencrypted -Value $false\"",
  ])
  shutdown_timeout = "15m"
}

build {
  sources = ["source.hyperv-iso.win2025"]

  provisioner "powershell" {
    scripts = ["${path.root}/scripts/baseline.ps1"]
  }

  provisioner "windows-update" {
    filters = ["exclude:$_.Title -like '*Preview*'", "include:$true"]
  }

  # Sysprep refuses to run with a reboot pending.
  provisioner "windows-restart" {}

  provisioner "powershell" {
    scripts = ["${path.root}/scripts/cleanup.ps1"]
  }

  # Always the last provisioner: nothing may change the image after it.
  provisioner "powershell" {
    scripts = ["${path.root}/scripts/sysprep.ps1"]
  }

  post-processor "shell-local" {
    execute_command    = ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "{{.Script}}"]
    tempfile_extension = ".ps1"
    inline = [
      "$ErrorActionPreference = 'Stop'",
      "$target = Join-Path '${var.image_store}' '${local.image_name}.vhdx'",
      "if (Test-Path $target) { throw \"$target exists; an image is never overwritten\" }",
      "Copy-Item 'output/${local.image_name}/Virtual Hard Disks/${local.image_name}.vhdx' $target",
      # Read-only: a differencing disk is corrupt the moment its parent changes.
      "Set-ItemProperty $target -Name IsReadOnly -Value $true",
    ]
  }

  post-processor "manifest" {
    output      = "packer-manifest.json"
    custom_data = { image = "${local.image_name}.vhdx", git_sha = var.git_sha }
  }
}
