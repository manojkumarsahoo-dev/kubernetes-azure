############################
# AZURE DATABASE FOR MYSQL - FLEXIBLE SERVER (replaces RDS)
# Private access only: reachable from inside the VNet (i.e. from AKS), not from the internet.
############################

resource "azurerm_private_dns_zone" "mysql" {
  name                = "shop.private.mysql.database.azure.com"
  resource_group_name = data.azurerm_resource_group.rg.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "mysql" {
  name                  = "mysql-vnet-link"
  resource_group_name   = data.azurerm_resource_group.rg.name
  private_dns_zone_name = azurerm_private_dns_zone.mysql.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  tags                  = var.tags
}

resource "azurerm_mysql_flexible_server" "mysql" {
  name                = "mysql-veeraops-${random_string.suffix.result}"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = var.location

  administrator_login    = var.mysql_admin_login
  administrator_password = var.mysql_admin_password

  sku_name = var.mysql_sku_name
  version  = "8.4"

  delegated_subnet_id = azurerm_subnet.mysql.id
  private_dns_zone_id = azurerm_private_dns_zone.mysql.id

  backup_retention_days = 7

  storage {
    size_gb = 20
  }

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.mysql]

  lifecycle {
    ignore_changes = [zone]
  }
}

resource "azurerm_mysql_flexible_database" "app" {
  name                = var.db_name
  resource_group_name = data.azurerm_resource_group.rg.name
  server_name         = azurerm_mysql_flexible_server.mysql.name
  charset             = "utf8mb4"
  collation           = "utf8mb4_unicode_ci"
}
