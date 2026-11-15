image_store = "D:\\Images"
vm_root     = "D:\\VMs\\staging"
switch_name = "LAN"
domain      = "staging.example.internal"

ssh_authorized_keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyOnlyForTheWorkedExample ansible@ci",
]

vms = {
  web01 = { image = "debian13-20261115-a1b2c3d.vhdx", os = "linux", role = "web" }
  web02 = { image = "debian13-20261115-a1b2c3d.vhdx", os = "linux", role = "web" }
  app01 = { image = "win2025-20261115-a1b2c3d.vhdx", os = "windows", role = "app", memory_gb = 8, vlan_id = 20 }
}
