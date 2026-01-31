project_name = "votingapp"
environment  = "prod"
location     = "eastus"

aks_node_count   = 3
aks_node_vm_size = "Standard_D4s_v3"
aks_min_nodes    = 3
aks_max_nodes    = 10

tags = {
  Project     = "VotingApp"
  Environment = "Production"
  Owner       = "Platform Team"
  CostCenter  = "Production"
  ManagedBy   = "Terraform"
}
