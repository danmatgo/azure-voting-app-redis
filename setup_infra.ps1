param (
    [string]$RepoName = "DanielMatapi/azure-voting-app-redis" # ¡Cambiar si tu repo es diferente!
)

Write-Host "Iniciando recreación de infraestructura desde cero en la suscripción activa..." -ForegroundColor Green

$RG = "votingapp-dev-rg"
$LOCATION = "eastus"
# Agregamos random para asegurar disponibilidad del ACR
$RandomSuffix = Get-Random -Maximum 9999
$ACR_NAME = "votingappdevacr$RandomSuffix"
$VNET_NAME = "votingapp-dev-vnet"
$SUBNET_NAME = "votingapp-dev-aks-subnet"
$WORKSPACE_NAME = "votingapp-dev-logs"
$AKS_NAME = "votingapp-dev-aks"
$APP_REG_NAME = "votingapp-github-actions-dev"
$TAGS = "Project=VotingApp Environment=Development Owner=Daniel"

# 1. Resource Group
Write-Host "1. Creando Resource Group..." -ForegroundColor Yellow
az group create --name $RG --location $LOCATION --tags $TAGS | Out-Null

# 2. ACR
Write-Host "2. Creando Azure Container Registry ($ACR_NAME)..." -ForegroundColor Yellow
az acr create --resource-group $RG --name $ACR_NAME --sku Basic --admin-enabled false --tags $TAGS | Out-Null
$ACR_ID = az acr show --name $ACR_NAME --resource-group $RG --query id -o tsv

# 3. VNet & Subnet
Write-Host "3. Creando Virtual Network..." -ForegroundColor Yellow
az network vnet create --resource-group $RG --name $VNET_NAME --address-prefix 10.0.0.0/16 --subnet-name $SUBNET_NAME --subnet-prefix 10.0.1.0/24 --tags $TAGS | Out-Null
$SUBNET_ID = az network vnet subnet show --resource-group $RG --vnet-name $VNET_NAME --name $SUBNET_NAME --query id -o tsv

# 4. Log Analytics
Write-Host "4. Creando form Log Analytics Workspace..." -ForegroundColor Yellow
az monitor log-analytics workspace create --resource-group $RG --workspace-name $WORKSPACE_NAME --location $LOCATION --tags $TAGS | Out-Null
$WORKSPACE_ID = az monitor log-analytics workspace show --resource-group $RG --workspace-name $WORKSPACE_NAME --query id -o tsv

# 5. AKS
Write-Host "5. Creando AKS cluster (ESTO TOMARÁ VARIOS MINUTOS)..." -ForegroundColor Yellow
az aks create `
  --resource-group $RG `
  --name $AKS_NAME `
  --node-count 1 `
  --node-vm-size Standard_B2s `
  --enable-cluster-autoscaler `
  --min-count 1 `
  --max-count 3 `
  --vnet-subnet-id $SUBNET_ID `
  --network-plugin kubenet `
  --network-policy calico `
  --pod-cidr 10.244.0.0/16 `
  --service-cidr 10.0.2.0/24 `
  --dns-service-ip 10.0.2.10 `
  --generate-ssh-keys `
  --workspace-resource-id $WORKSPACE_ID `
  --enable-addons monitoring `
  --tags $TAGS | Out-Null

Write-Host "6. Conectando AKS con ACR..." -ForegroundColor Yellow
az aks update -n $AKS_NAME -g $RG --attach-acr $ACR_NAME | Out-Null

# 6. OIDC
Write-Host "7. Configurando OIDC para GitHub Actions..." -ForegroundColor Yellow
$AppRegJson = az ad app create --display-name $APP_REG_NAME
$APP_CLIENT_ID = ($AppRegJson | ConvertFrom-Json).appId
$APP_OBJECT_ID = ($AppRegJson | ConvertFrom-Json).id

az ad sp create --id $APP_CLIENT_ID | Out-Null

$RG_ID = az group show --name $RG --query id -o tsv
# Esperar un momento a que el SP se propague para evitar errores de rol
Start-Sleep -Seconds 15
az role assignment create --assignee $APP_CLIENT_ID --role "Contributor" --scope $RG_ID | Out-Null

$FED_CRED_JSON = @"
{
  "name": "GitHubActionsFederation",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$RepoName:ref:refs/heads/main",
  "description": "Permite deploy a GitHub Actions",
  "audiences": ["api://AzureADTokenExchange"]
}
"@
$FED_CRED_JSON | Out-File fedcred.json -Encoding utf8
az ad app federated-credential create --id $APP_OBJECT_ID --parameters fedcred.json | Out-Null
Remove-Item fedcred.json

Write-Host "`n=======================================================" -ForegroundColor Cyan
Write-Host "                 ¡Despliegue exitoso!                  " -ForegroundColor Cyan
Write-Host "=======================================================" -ForegroundColor Cyan
Write-Host "Ve a GitHub -> Settings -> Secrets and Variables y actualiza:"
Write-Host "AZURE_CLIENT_ID       : $APP_CLIENT_ID"
Write-Host "AZURE_TENANT_ID       : $(az account show --query tenantId -o tsv)"
Write-Host "AZURE_SUBSCRIPTION_ID : $(az account show --query id -o tsv)"
Write-Host "`nTu nuevo ACR se llama: $ACR_NAME" (Asegúrate de cambiar esto en tus workflows de GitHub)
Write-Host "=======================================================" -ForegroundColor Cyan
