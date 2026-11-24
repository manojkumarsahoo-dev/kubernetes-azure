terraform {
  required_version = ">= 1.15"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id

  # The sandbox identity cannot register resource providers (403 on */register/action).
  # The providers this config needs must already be registered by the administrator:
  # Microsoft.ContainerService, Microsoft.Network, Microsoft.ContainerRegistry,
  # Microsoft.DBforMySQL, Microsoft.Storage, Microsoft.Compute.
  resource_provider_registrations = "none"
}

resource "random_string" "suffix" {
  length  = 5
  upper   = false
  special = false
}

############################
# EXISTING SANDBOX RESOURCE GROUP
############################

data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

############################
# NETWORK (replaces VPC / subnets / NAT)
############################

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-veeraops-shop"
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  address_space       = ["10.0.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "aks" {
  name                 = "snet-aks"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Dedicated, delegated subnet for the private MySQL Flexible Server
resource "azurerm_subnet" "mysql" {
  name                 = "snet-mysql"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]

  delegation {
    name = "mysql-flexible-server"

    service_delegation {
      name    = "Microsoft.DBforMySQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

############################
# CONTAINER REGISTRY (replaces ECR)
############################

resource "azurerm_container_registry" "acr" {
  name                = "${var.acr_name_prefix}${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location
  sku                 = "Basic"
  # Sandbox-friendly: avoids requiring Microsoft.Authorization/roleAssignments/write.
  # The workflow creates a Kubernetes imagePullSecret using these credentials.
  admin_enabled       = true
  tags                = var.tags
}

############################
# AKS CLUSTER (replaces EKS + node group + IAM roles + addons)
############################

resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = data.azurerm_resource_group.rg.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free"

  default_node_pool {
    name                 = "system"
    vm_size              = var.node_vm_size
    vnet_subnet_id       = azurerm_subnet.aks.id
    node_count           = var.node_count
    auto_scaling_enabled = true
    min_count            = var.node_min_count
    max_count            = var.node_max_count
    os_disk_size_gb      = 64
  }

  # Managed identities are unavailable in this training sandbox.
  # Supply an administrator-provisioned service principal that already has
  # the required permissions on this existing resource group and VNet.
  service_principal {
    client_id     = var.aks_service_principal_client_id
    client_secret = var.aks_service_principal_client_secret
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    pod_cidr            = "192.168.0.0/16"
    service_cidr        = "10.2.0.0/16"
    dns_service_ip      = "10.2.0.10"
    load_balancer_sku   = "standard"
  }

  tags = var.tags

  lifecycle {
    ignore_changes = [default_node_pool[0].node_count]

    precondition {
      condition     = var.node_min_count <= var.node_count && var.node_count <= var.node_max_count
      error_message = "Require node_min_count <= node_count <= node_max_count."
    }
  }
}

# In restricted training subscriptions, the service principal often cannot create
# Azure role assignments (Microsoft.Authorization/roleAssignments/write).
# ACR admin credentials are used by the workflow to create a Kubernetes
# imagePullSecret instead, so no AcrPull role assignment is needed.
