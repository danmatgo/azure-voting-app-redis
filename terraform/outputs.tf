output "resource_group_name" {
  description = "Nombre del Resource Group"
  value       = azurerm_resource_group.main.name
}

output "acr_login_server" {
  description = "URL del ACR"
  value       = azurerm_container_registry.main.login_server
}

output "acr_name" {
  description = "Nombre del ACR"
  value       = azurerm_container_registry.main.name
}

output "aks_cluster_name" {
  description = "Nombre del AKS"
  value       = azurerm_kubernetes_cluster.main.name
}

output "aks_cluster_id" {
  description = "ID del AKS"
  value       = azurerm_kubernetes_cluster.main.id
}

output "aks_get_credentials_command" {
  description = "Comando para obtener credenciales del AKS"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.main.name} --name ${azurerm_kubernetes_cluster.main.name} --overwrite-existing"
}

output "acr_login_command" {
  description = "Comando para obtener credenciales del ACR"
  value       = "az acr login --name ${azurerm_container_registry.main.name}"
}
