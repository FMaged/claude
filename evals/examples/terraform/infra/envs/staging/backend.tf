# Address, lock, and credentials come from the TF_HTTP_* variables the CI template sets,
# with TF_STATE_NAME=staging.
terraform {
  backend "http" {}
}
