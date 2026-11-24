variable "subscription_id" {
  description = "Azure subscription ID. Leave null to use ARM_SUBSCRIPTION_ID from the environment."
  type        = string
  default     = null
}

variable "aks_service_principal_client_id" {
  description = "Client ID of an administrator-provisioned service principal for AKS (managed identities are not supported in this sandbox)."
  type        = string
  sensitive   = true
}

variable "aks_service_principal_client_secret" {
  description = "Client secret of the administrator-provisioned AKS service principal."
  type        = string
  sensitive   = true
}

variable "resource_group_name" {
  description = "Existing sandbox resource group name. Override via TF_VAR_resource_group_name / AZURE_RESOURCE_GROUP to match your active sandbox."
  type        = string
  default     = "1-9146790e-playground-sandbox"
}

variable "location" {
  description = "Azure region for resources created inside the existing sandbox resource group. Must be allowed by the sandbox (for example, westus2)."
  type        = string
  default     = "westus2"
}

variable "cluster_name" {
  description = "Name of the AKS cluster."
  type        = string
  default     = "aks-veeraops-shop"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version. null uses the region's default supported version."
  type        = string
  default     = null
}

variable "node_vm_size" {
  description = "VM size for the AKS node pool. Change if your subscription has no quota or regional availability for this size."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_count" {
  description = "Initial AKS node count; Azure sandbox permits at most 3 nodes per cluster."
  type        = number
  default     = 2
  validation {
    condition     = var.node_count >= 1 && var.node_count <= 3
    error_message = "Azure sandbox AKS node_count must be between 1 and 3."
  }
}

variable "node_min_count" {
  description = "Minimum AKS node count."
  type        = number
  default     = 2
  validation {
    condition     = var.node_min_count >= 1 && var.node_min_count <= 3
    error_message = "Azure sandbox AKS node_min_count must be between 1 and 3."
  }
}

variable "node_max_count" {
  description = "Maximum AKS node count; Azure sandbox permits at most 3."
  type        = number
  default     = 3
  validation {
    condition     = var.node_max_count >= 1 && var.node_max_count <= 3
    error_message = "Azure sandbox AKS node_max_count must be between 1 and 3."
  }
}

variable "acr_name_prefix" {
  description = "Prefix for the container registry name (a random suffix is added for global uniqueness). Lowercase letters and digits only."
  type        = string
  default     = "veeraopsshop"
}

variable "mysql_sku_name" {
  description = "SKU name for Azure Database for MySQL."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "mysql_admin_login" {
  description = "MySQL admin username. Note: 'admin', 'root', and similar names are reserved by Azure."
  type        = string
  default     = "shopadmin"
}

variable "mysql_admin_password" {
  description = "MySQL admin password (8-128 characters, mixing uppercase, lowercase, digits, and symbols). Supply via TF_VAR_mysql_admin_password / GitHub secret; never commit it."
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "Database name used by the backend (backend/test.sql also creates it if missing)."
  type        = string
  default     = "cloud"
}

variable "tags" {
  description = "Default tags applied to provisioned resources."
  type        = map(string)
  default = {
    Environment = "dev"
    Project     = "veeraops-shop"
    Owner       = "veeraops"
  }
}
