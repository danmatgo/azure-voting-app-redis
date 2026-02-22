# 🚀 DEPLOYMENT CROSS-ACCOUNT - GUÍA RÁPIDA

## Arquitectura

```
CUENTA PERSONAL (macapixes1@hotmail.com)     CUENTA TRABAJO (estebanmatapi@exsis.com.co)
├── tfstate-rg (Azure Storage)               └── AKS Cluster
├── ACR (votingappdevacr)                        ├── Conecta a ACR de cuenta personal
├── Resource Group, VNet, Subnet                 └── Kubeconfig para GitHub Actions
└── Log Analytics
```

---

## Paso 1: Login a Cuenta Personal

```powershell
az logout
az login --use-device-code
# Usar: macapixes1@hotmail.com
```

---

## Paso 2: Verificar Backend Existe

```powershell
az group show --name tfstate-rg
az storage account show --name tfstatevoting2390 --resource-group tfstate-rg
```

Si no existe, créalo:
```powershell
az group create --name tfstate-rg --location eastus
az storage account create --name tfstatevoting2390 --resource-group tfstate-rg --location eastus --sku Standard_LRS
az storage container create --name tfstate --account-name tfstatevoting2390
```

---

## Paso 3: Terraform en Cuenta Personal

```powershell
cd terraform
terraform init                                    # Conecta al backend
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

Esto crea: ACR, VNet, Resource Group, Log Analytics

---

## Paso 4: Login a Cuenta de Trabajo

```powershell
az logout
az login --use-device-code
# Usar: estebanmatapi@exsis.com.co
```

---

## Paso 5: Terraform AKS en Cuenta de Trabajo

```powershell
terraform plan -var-file="environments/dev.tfvars"
terraform apply -var-file="environments/dev.tfvars"
```

Esto crea: AKS cluster

---

## Paso 6: Role Assignment Cross-Account

Obtener IDs:
```powershell
# En cuenta personal
az login # (macapixes1)
$ACR_ID = az acr show --name votingappdevacr --query id -o tsv

# En cuenta de trabajo
az login # (estebanmatapi)
$AKS_IDENTITY = az aks show --name votingapp-dev-aks --resource-group votingapp-dev-rg --query identityProfile.kubeletidentity.objectId -o tsv

# Asignar rol
az role assignment create --assignee $AKS_IDENTITY --role AcrPull --scope $ACR_ID
```

---

## Paso 7: Obtener Kubeconfig

```powershell
az aks get-credentials --name votingapp-dev-aks --resource-group votingapp-dev-rg --file ./kubeconfig-temp

# Verificar
kubectl get nodes --kubeconfig ./kubeconfig-temp
```

---

## Siguiente: Deploy de la App

Una vez la infraestructura esté lista, el pipeline de GitHub Actions se encarga del resto.
