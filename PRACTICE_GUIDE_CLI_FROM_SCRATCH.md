# 💻 Guía Práctica: Infraestructura desde cero con Azure CLI

> **Objetivo**: Recrear toda la infraestructura del proyecto usando únicamente comandos de Azure CLI, consolidando todo en tu **Suscripción de Trabajo** (ahora que tienes permisos para OIDC y App Registrations).
> **Por qué importa**: Entender cómo hacer todo por CLI antes de automatizar con Terraform es vital. Ayuda a interiorizar qué recursos existen y cómo se interconectan.

---

## 1. Preparación y Variables

Abre tu terminal de PowerShell y asegúrate de estar logueado en tu cuenta de trabajo:

```powershell
az login
az account show # Verifica que es tu cuenta de trabajo
```

Vamos a definir algunas variables para facilitar los comandos:

```powershell
$RG="votingapp-dev-rg"
$LOCATION="eastus"
$ACR_NAME="votingappdevacr$(Get-Random -Maximum 9999)" # Añadimos random por si el nombre global choca
$VNET_NAME="votingapp-dev-vnet"
$SUBNET_NAME="votingapp-dev-aks-subnet"
$WORKSPACE_NAME="votingapp-dev-logs"
$AKS_NAME="votingapp-dev-aks"
$APP_REG_NAME="votingapp-github-actions-dev"

$TAGS="Project=VotingApp Environment=Development Owner=Daniel"
```

---

## 2. Resource Group y Container Registry (ACR)

Primero creamos el contenedor lógico y el registro de imágenes.

```powershell
# 1. Crear Resource Group
az group create --name $RG --location $LOCATION --tags $TAGS

# 2. Crear Azure Container Registry (SKU Basic para ahorrar)
az acr create --resource-group $RG --name $ACR_NAME --sku Basic --admin-enabled false --tags $TAGS

# 3. Obtener el ID del ACR (lo necesitaremos luego para permisos)
$ACR_ID = az acr show --name $ACR_NAME --resource-group $RG --query id -o tsv
```

---

## 3. Redes (VNet) y Monitoreo (Log Analytics)

Vamos a configurar la red virtual de donde AKS tomará las IPs, y el workspace para guardar los logs.

```powershell
# 1. Crear VNet y Subnet
az network vnet create `
  --resource-group $RG `
  --name $VNET_NAME `
  --address-prefix 10.0.0.0/16 `
  --subnet-name $SUBNET_NAME `
  --subnet-prefix 10.0.1.0/24 `
  --tags $TAGS

$SUBNET_ID = az network vnet subnet show `
  --resource-group $RG `
  --vnet-name $VNET_NAME `
  --name $SUBNET_NAME `
  --query id -o tsv

# 2. Crear Log Analytics Workspace (Para AKS Container Insights)
az monitor log-analytics workspace create `
  --resource-group $RG `
  --workspace-name $WORKSPACE_NAME `
  --location $LOCATION `
  --tags $TAGS

$WORKSPACE_ID = az monitor log-analytics workspace show `
  --resource-group $RG `
  --workspace-name $WORKSPACE_NAME `
  --query id -o tsv
```

---

## 4. Azure Kubernetes Service (AKS)

Ahora creamos el clúster usando la red y el monitoreo que acabamos de crear. Además, le configuramos autoscaling con VMs económicas (`Standard_B2s`).

```powershell
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
  --tags $TAGS
```
*(Nota: Este comando tomará alrededor de 5-10 minutos en completarse)*

---

## 5. Permisos Internos: AKS -> ACR

El clúster necesita descargar las imágenes de contenedores desde nuestro registro privado. 

```powershell
# 1. Otorgamos el rol de AcrPull a la identidad que maneja el clúster
az aks update -n $AKS_NAME -g $RG --attach-acr $ACR_NAME

# Verificar que puedes conectarte al clúster
az aks get-credentials --resource-group $RG --name $AKS_NAME --overwrite-existing
kubectl get nodes
```

---

## 6. Identidad para GitHub Actions (OIDC)

Como ahora **tienes permisos en tu suscripción de trabajo**, podemos crear la aplicación OIDC directamente aquí para que GitHub Actions pueda hacer los despliegues sin usar contraseñas.

```powershell
# 1. Crear la App Registration
$APP_REG = az ad app create --display-name $APP_REG_NAME
$APP_CLIENT_ID = ($APP_REG | ConvertFrom-Json).appId
$APP_OBJECT_ID = ($APP_REG | ConvertFrom-Json).id

# 2. Crear el Service Principal asociado
az ad sp create --id $APP_CLIENT_ID

# 3. Darle permisos de Contributor sobre el Resource Group a la App
$RG_ID = az group show --name $RG --query id -o tsv
az role assignment create --assignee $APP_CLIENT_ID --role "Contributor" --scope $RG_ID

# 4. Configurar la Federación OIDC para GitHub
# REEMPLAZA "TU_USUARIO_GITHUB/azure-voting-app-redis" con tu repo real
$REPO = "TU_USUARIO_GITHUB/azure-voting-app-redis"

$FED_CRED_JSON = @"
{
  "name": "GitHubActionsFederation",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:$REPO:ref:refs/heads/main",
  "description": "Permite deploy a GitHub Actions",
  "audiences": ["api://AzureADTokenExchange"]
}
"@

$FED_CRED_JSON | Out-File fedcred.json -Encoding utf8

az ad app federated-credential create --id $APP_OBJECT_ID --parameters fedcred.json
```

---

## 7. Actualizar GitHub Secrets

Para que el pipeline de GitHub siga funcionando en esta nueva infraestructura unificada, debes ir a **Settings > Secrets and variables > Actions** en tu repositorio y actualizar los siguientes secretos:

1. `AZURE_CLIENT_ID`: Pon el valor de `$APP_CLIENT_ID`
2. `AZURE_TENANT_ID`: Pon el valor de tu Tenant (puedes verlo con `az account show --query tenantId -o tsv`)
3. `AZURE_SUBSCRIPTION_ID`: Pon tu Suscripción (puedes verlo con `az account show --query id -o tsv`)
4. Cambia las variables en tu de flujo de GitHub (`.github/workflows`) para apuntar al nuevo `$ACR_NAME`.

---

¡Listo! Ya tienes una arquitectura completamente reconstruida a puro estilo CLI. Lo mejor es que ahora no sufriremos el temido "Context Switching" porque el OIDC, ACR y AKS viven en paz en la **Suscripción de Trabajo**.
