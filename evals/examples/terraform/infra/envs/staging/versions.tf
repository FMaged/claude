terraform {
  required_version = ">= 1.4.0" # terraform_data

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "= 1.2.1"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "= 2.8.1"
    }
    local = {
      source  = "hashicorp/local"
      version = "= 2.9.1"
    }
  }
}
