project_name = "votingapp"
environment  = "dev"
location     = "eastus"

aks_node_count   = 1
aks_node_vm_size = "Standard_B2s"
aks_min_nodes    = 1
aks_max_nodes    = 3

tags = {
  Project     = "VotingApp"
  Environment = "Development"
  Owner       = "Daniel Matapi"
  CostCenter  = "Training"
  ManagedBy   = "Terraform"
}
