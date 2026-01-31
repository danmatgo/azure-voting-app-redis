terraform {
  required_version = ">= 1.0"

  backend "azurerm" {
    resource_group_name  = "tfstate-rg"
    storage_account_name = "tfstatevoting2390"
    container_name       = "tfstate"
    key                  = "votingapp-dev.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
