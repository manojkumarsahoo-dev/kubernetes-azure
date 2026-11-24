# Remote state in an Azure Storage account (replaces the S3 backend).
# Backend settings (resource_group_name, storage_account_name, container_name,
# key, and access_key) are supplied dynamically via `terraform init -backend-config=...`.
#
# The GitHub workflow (.github/workflows/infra-aks.yml) supplies these values at init time.
terraform {
  backend "azurerm" {}
}
