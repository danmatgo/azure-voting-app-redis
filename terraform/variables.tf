variable "project_name" {
  description = "Nombre del proyecto"
  type        = string
  default     = "votingapp"
}

variable "environment" {
  description = "Ambiente (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "El ambiente debe ser dev, staging o prod"
  }
}

variable "location" {
  description = "Region de Azure"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags para recursos"
  type        = map(string)
  default = {
    Project    = "VotingApp"
    Enviroment = "Development"
    Owner      = "Daniel Matapi"
    CostCenter = "Training"
    ManagedBy  = "Terraform"
  }
}

variable "aks_node_count" {
  description = "Numero de nodos"
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "Tamaño de VM"
  type        = string
  default     = "Standard_D2as_v4"
}

variable "aks_enable_autoscaling" {
  description = "Habilitar autoscaling"
  type        = bool
  default     = false
}

variable "aks_min_nodes" {
  description = "Minimo de nodos"
  type        = number
  default     = 1
}

variable "aks_max_nodes" {
  description = "Maximo de nodos"
  type        = number
  default     = 3
}

variable "vnet_address_space" {
  description = "Address space VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "aks_subnet_prefix" {
  description = "Prefix subnet AKS"
  type        = string
  default     = "10.0.1.0/24"
}
