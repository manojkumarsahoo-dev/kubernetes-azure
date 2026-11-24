output "resource_group_name" {
  value = data.azurerm_resource_group.rg.name
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "acr_name" {
  value = azurerm_container_registry.acr.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "mysql_fqdn" {
  value = azurerm_mysql_flexible_server.mysql.fqdn
}

output "mysql_admin_login" {
  value = azurerm_mysql_flexible_server.mysql.administrator_login
}

output "get_credentials_command" {
  value = "az aks get-credentials --resource-group ${data.azurerm_resource_group.rg.name} --name ${azurerm_kubernetes_cluster.aks.name}"
}
