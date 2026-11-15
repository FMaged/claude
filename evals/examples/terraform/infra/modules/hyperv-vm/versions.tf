terraform {
  required_version = ">= 1.4.0" # terraform_data

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = ">= 1.2.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }
  }
}
